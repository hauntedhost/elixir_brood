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

  # Private API

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
    ip_addresses = get_all_ip_addresses(ip_address)

    state = %{
      ip_address: ip_address,
      ip_addresses: ip_addresses
    }

    {:ok, brood} = GenServer.start_link(__MODULE__, state)
    :global.register_name(@name, brood)

    join_nodes(state)

    brood
  end

  # get local ip address
  defp get_ip_address do
    IO.puts("getting local ip address ...")

    ip = :os.cmd('ip route get 8.8.8.8 | awk \'{print $NF; exit}\'')
    |> List.to_string
    |> String.rstrip(?\n)

    IO.inspect(ip)
    ip
  end

  # get all ip addresses in LAN
  def get_all_ip_addresses(localhost_ip) do
    IO.puts("getting ip addresses in LAN ...")

    first_ip = localhost_ip
    |> String.split(".")
    |> List.update_at(-1, fn(_) -> "0" end)
    |> Enum.join(".")

    {xml, _rest} = :os.cmd('nmap -sn -oX - #{first_ip}/24')
    |> :xmerl_scan.string

    :xmerl_xpath.string('/nmaprun/host', xml)
    |> Enum.map(fn(host) ->
      hostname = :xmerl_xpath.string('/host/hostnames/hostname', host)
      |> extract_first(:name)
      address = :xmerl_xpath.string('/host/address', host)
      |> extract_first(:addr)
      {hostname, address}
    end)
  end

  defp extract_first([], _), do: nil

  defp extract_first([first_el|_rest], attr_name) do
    first_el
    |> xmlElement(:attributes)
    |> Enum.find(fn(attr) ->
      xmlAttribute(attr, :name) == attr_name
    end)
    |> xmlAttribute(:value)
    |> List.to_string
  end

  defp join_nodes(state) do
    IO.puts("joining nodes ...")

    state.ip_addresses
    |> Enum.reject(fn({hostname, ip_address}) ->
      ip_address == state.ip_address ||
      is_nil(hostname)
    end)
    |> Enum.each(&join_node/1)
  end

  defp join_node({hostname, ip_address}) do
    node = "#{hostname}@#{ip_address}" |> String.to_atom
    Task.async(fn() ->
      case Node.connect(node) do
        true -> IO.puts("connected to #{node}")
        _    -> IO.puts("unable to connect to #{node}")
      end
    end)
  end
end
