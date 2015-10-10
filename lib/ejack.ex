defmodule EJack do
  use Application

  def start(_type, _args) do
    EJack.TCPIT.start
  end

end

defmodule EJack.TCPIT do
  use Bitwise

  def start() do
    import Supervisor.Spec
    children = [
      supervisor(Task.Supervisor, [[name: EJack.TaskSupervisor]]),
      worker(Task, [EJack.TCPIT, :listen, [4040]])
      ]
    opts = [strategy: :one_for_one, name: EJack.Supervisor]
    Supervisor.start_link(children, opts)
  end

                
  def listen(port) do
    #{:ok, socket} = :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true])
    #{:ok, socket} = :gen_tcp.listen(port, [:binary, packet: 0, active: false, reuseaddr: true])
    {:ok, socket} = :gen_tcp.listen(port, [:binary, packet: 0, active: true, reuseaddr: true])
    IO.puts "Accepting connections on port #{port}"
    loop_acceptor(socket)
  end
  defp loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    #{:ok, pid} = Task.Supervisor.start_child(EJack.TaskSupervisor, fn -> handshake(client) end)
    #:gen_tcp.controlling_process(client, pid)
    #loop_acceptor(socket)

    {:ok, pid} = Task.Supervisor.start_child(EJack.TaskSupervisor, fn -> loop_acceptor(socket) end)
    handshake(client)
  end
  defp handshake(socket) do
    guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    packet = read_line(socket)
    IO.puts packet
    key = hd for line <- String.split(packet, "\n"),
        String.contains?(line, ":"),
        [left, right] = Enum.take(String.split(line, ":"), 2),
        left == "Sec-WebSocket-Key",
        do: String.strip(right)
    response_key = :crypto.hash(:sha, key <> guid) |> Base.encode64
    response = "HTTP/1.1 101 Web Socket Protocol Handshake\r\n" <>
    "Upgrade: WebSocket\r\n" <>
    "Connection: Upgrade\r\n" <>
    "WebSocket-Origin: http://localhost:8888\r\n" <>
    "WebSocket-Location: ws://localhost:9876/\r\n" <>
    "WebSocket-Protocol: sample\r\n" <>
    "Sec-WebSocket-Accept: " <>
    response_key <>
    "\r\n\r\n"
    IO.puts response
    write_line(response, socket)

    serve(socket, "")
  end

  defp binary_index(bin, i) do
    <<result>> = binary_part(bin, i, 1)
    result
  end

  def parse_data(data) do
    masked_len = binary_index(data, 1)
    len = masked_len &&& 0x7f
    # if len > 0?
    mask_key = binary_part(data, 2, 4)
    masked_data = binary_part(data, 6, len)
    parsed = for i <- 0..(len-1),  into: "", do: << binary_index(masked_data,i) ^^^ binary_index(mask_key,rem(i,4)) >>

    realsize = div(bit_size(data),8)
    if realsize > 6+len do
      parsed = parsed <> parse_data(binary_part(data, 6+len, realsize-(6+len)))
    end
    parsed
  end

  defp read_string(string) do
    {len_str, string} = String.split_at(string, 3)
    len = String.to_integer(len_str)
    String.split_at(string, len)
  end

  defp int_to_string(int, len) do
    str = Integer.to_string(int) |> String.rjust(3, 48)
  end

  defp serve(socket, current_data) do
    IO.puts("casing with #{div(bit_size(current_data),8)}")
    case current_data do
      "PIN" <> rest ->
        IO.puts("ping!")
        {_, current_data} = String.split_at(current_data, 4)

      "000" <> rest ->
        IO.puts("start game!")
        {_, current_data} = String.split_at(current_data, 3)

      "001" <> rest ->
        IO.puts("player hit")
        {_, current_data} = String.split_at(current_data, 3)

      "002" <> rest ->
        IO.puts("player stayed")
        {_, current_data} = String.split_at(current_data, 3)

      "003" <> rest ->
        IO.puts("player busted")
        {_, current_data} = String.split_at(current_data, 3)

      "005" <> rest ->
        IO.puts("player name")
        {_, current_data} = String.split_at(current_data, 3)
        {name, current_data} = read_string(current_data)
        IO.puts(name)

      "010" <> rest ->
        IO.puts("host something")
        {_, current_data} = String.split_at(current_data, 3)
        {host_code, current_data} = String.split_at(current_data, 4)
        if host_code == "0000" do
          IO.puts("become host")
          host_code = "DDDA"
          write_wb_packet(int_to_string(10, 3) <> host_code, socket)
        else
          IO.puts("join host #{host_code}")
          write_wb_packet(int_to_string(1, 3) <> "01", socket)
        end

      _ -> 
        IO.puts("reading some more data, have #{div(bit_size(current_data),8)}")
        current_data = current_data <> parse_data(read_line(socket))
        IO.puts("read more data, have #{div(bit_size(current_data),8)}")
      #_ -> IO.puts("not enough data/invalid/unknown message")
    end
    serve(socket, current_data)
  end
  defp read_line(socket) do
    #{:ok, data} = :gen_tcp.recv(socket, 0)
    #data
    data = receive do
      #{:ok, data} -> data
      {:tcp, port, data} -> data
    end
    IO.puts("READ LINE, have #{bit_size(data)} /8 =  #{div(bit_size(data),8)}")
    data
  end
  defp read_line_low_block(socket) do
    case :gen_tcp.recv(socket, 0, 100) do
      {:ok, data} -> data
      {:error, _} -> ""
    end
  end
  defp write_line(line, socket) do
    IO.puts("sending:#{line}")
    :gen_tcp.send(socket, line)
  end
  defp write_wb_packet(line, socket) do
    IO.puts("sending:#{line}")
    :gen_tcp.send(socket, <<129, String.length(line)>> <> line)
  end
end

defmodule EJack.Asy do 
  def start_link() do 
    Agent.start_link fn -> HashDict.new end
  end
  def get(agent, key) do 
    Agent.get(agent, fn dict -> HashDict.get(dict, key) end)
  end
  def put(agent, key, value) do 
    Agent.update(agent, fn dict -> HashDict.put(dict, key, value) end)
  end
end

