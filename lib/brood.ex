defmodule Brood do
  use GenServer
  require Record
  Record.defrecord(:xmlAttribute, Record.extract(:xmlAttribute,
    from_lib: "xmerl/include/xmerl.hrl"))
  Record.defrecord(:xmlElement, Record.extract(:xmlElement,
    from_lib: "xmerl/include/xmerl.hrl"))

  @name :brood

  def start do
    brood || spawn_brood
  end

  def ip_address do
    GenServer.call(brood, :ip_address)
  end

  def ip_addresses do
    GenServer.call(brood, :ip_addresses)
  end

  def consul_agents do
    GenServer.call(brood, :consul_agents)
  end

  # GenServer

  def handle_call(:ip_address, _from, state) do
    {:reply, state.ip_address, state}
  end

  def handle_call(:ip_addresses, _from, state) do
    {:reply, state.ip_addresses, state}
  end

  def handle_call(:consul_agents, _from, state) do
    {:reply, state.consul_agents, state}
  end

  # get local ip address
  def get_ip_address do
    IO.inspect("getting local ip address ...")
    :os.cmd('ip route get 8.8.8.8 | awk \'{print $NF; exit}\'')
    |> List.to_string
    |> String.rstrip(?\n)
  end

  # get all ip addresses in LAN
  def get_all_ip_addresses do
    IO.inspect("getting ip address in LAN ...")
    {xml, _rest} = :os.cmd('nmap -sn -oX - 192.168.1.0/24')
    |> :xmerl_scan.string
    :xmerl_xpath.string('/nmaprun/host/address', xml)
    |> Enum.map(fn(address) ->
      xmlElement(address, :attributes)
      |> Enum.find(fn(attr) ->
        xmlAttribute(attr, :name) == :addr
      end)
      |> xmlAttribute(:value)
      |> List.to_string
    end)
  end

  # Private API

  def is_consul_agent?(ip) do
    case System.cmd("curl", ["#{ip}:8500/v1/agent/self"]) do
      {_, 0} -> true
      _      -> false
    end
  end

  defp consul_agents(ips) do
    Enum.filter(ips, &is_consul_agent?/1)
  end

  # lookup brood pid
  defp brood do
    case :global.whereis_name(@name) do
      :undefined -> nil
      brood_pid  -> brood_pid
    end
  end

  # spawn brood, register brood as a global
  defp spawn_brood do
    ip_address = get_ip_address
    ip_addresses = get_all_ip_addresses
    start_consul(ip_address)
    consul_agents = consul_agents(ip_addresses)

    state = %{
      ip_address: ip_address,
      ip_addresses: ip_addresses,
      consul_agents: consul_agents
    }

    {:ok, brood} = GenServer.start_link(__MODULE__, state)
    :global.register_name(@name, brood)
    brood
  end

  def start_consul(ip_address) do
    case consul_info(ip_address) do
      {_, 1} ->
        IO.inspect("starting consul ...")
        Task.async(fn() ->
          System.cmd("consul", [
            "agent",
            "-data-dir=/tmp/consul",
            "-client=#{ip_address}"
          ])
        end)
      _ ->
        IO.inspect("consul already started ...")
        :ok
    end
  end

  def consul_info(ip_address) do
    System.cmd("consul", [
      "info",
      "--rpc-addr=#{ip_address}:8400"
    ])
  end
end
