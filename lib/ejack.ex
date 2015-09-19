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
    {:ok, socket} = :gen_tcp.listen(port, [:binary, packet: 0, active: false, reuseaddr: true])
    IO.puts "Accepting connections on port #{port}"
    loop_acceptor(socket)
  end
  defp loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    {:ok, pid} = Task.Supervisor.start_child(EJack.TaskSupervisor, fn -> handshake(client) end)
    :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket)
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
    for i <- 0..(len-1),  into: "", do: << binary_index(masked_data,i) ^^^ binary_index(mask_key,rem(i,4)) >>
  end

  defp serve(socket, current_data) do
    current_data = current_data <> parse_data(read_line(socket))
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

      "010" <> rest ->
        IO.puts("joining host")
        {_, current_data} = String.split_at(current_data, 3)

      _ -> IO.puts("not enough data/invalid/unknown message")
        {code, current_data} = String.split_at(current_data, 3)
        IO.puts("code: #{code}")
    end
    serve(socket, current_data)
  end
  defp read_line(socket) do
    {:ok, data} = :gen_tcp.recv(socket, 0)
    data
  end
  defp write_line(line, socket) do
    :gen_tcp.send(socket, line)
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

