defmodule Brood do
  require Record
  Record.defrecord(:xmlAttribute,
    Record.extract(:xmlAttribute,
      from_lib: "xmerl/include/xmerl.hrl"
    )
  )

  Record.defrecord(:xmlElement,
    Record.extract(:xmlElement,
      from_lib: "xmerl/include/xmerl.hrl"
    )
  )

  def loop(state \\ %{}) do
    # ensure_consul(state)
    receive do
      {:ip_address, pid} ->
        ip_address = get_ip_address(state)
        send(pid, ip_address)
        loop(Map.merge(state, %{ip_address: ip_address}))
      {:ip_addresses, pid} ->
        ip_addresses = get_all_ip_addresses(state)
        send(pid, ip_addresses)
        loop(Map.merge(state, %{ip_addresses: ip_addresses}))
    end
    loop(state)
  end

  # def ensure_consul(state) do
  #   consul info
  # end

  def get_ip_address(state = %{ip_address: ip_address}) do
    IO.inspect("returning existing ip address")
    ip_address
  end

  def get_ip_address(state) do
    IO.inspect("calculating ip address")
    :os.cmd('ip route get 8.8.8.8 | awk \'{print $NF; exit}\'')
    |> List.to_string
    |> String.rstrip(?\n)
  end

  def get_all_ip_addresses(state = %{ip_addresses: ip_addresses}) do
    IO.inspect("returning existing ip addresses")
    ip_addresses
  end

  def get_all_ip_addresses(state) do
    IO.inspect("calculating ip addresses")
    {xml, _rest} = :os.cmd('nmap -sn -oX - 192.168.1.0/24')
    |> :xmerl_scan.string

    :xmerl_xpath.string('/nmaprun/host/address', xml)
    |> Enum.map(fn(address) ->
      xmlElement(address, :attributes)
      |> Enum.find(fn(attr) ->
        xmlAttribute(attr, :name) == :addr
      end)
      |> xmlAttribute(:value)
    end)
  end
end
