defmodule Payload do
  defstruct [
    :data,
    delay: 0
  ]
end

defmodule ExRabbitMQ.RPCTest do
  use ExUnit.Case, async: false

  setup_all do
    {:ok, _pid} = ExRabbitMQ.Connection.Pool.Supervisor.start_link([])
    :ok
  end

  @grace 3000

  test "client can request and get response from server" do
    payload = %Payload{data: UUID.uuid4()}
    correlation_id = UUID.uuid4()

    {:ok, client} = TestClient.start()
    {:ok, server} = TestServer.start()

    :ok = TestClient.test_request(client, payload, correlation_id)

    assert_receive {:send_request, {:ok, ^correlation_id}}
    assert_receive {:received_request, ^correlation_id, ^payload}
    assert_receive {:received_response, ^correlation_id, {:ok, ^payload}}
    refute_receive {:received_response, ^correlation_id, {:error, :expired}}, @grace

    GenServer.stop(client)
    GenServer.stop(server)
  end

  test "request can expire" do
    payload = %Payload{delay: @grace, data: UUID.uuid4()}
    correlation_id = UUID.uuid4()

    {:ok, client} = TestClient.start()
    {:ok, server} = TestServer.start()

    :ok = TestClient.test_request(client, payload, correlation_id)

    assert_receive {:send_request, {:ok, ^correlation_id}}
    assert_receive {:received_request, ^correlation_id, ^payload}
    assert_receive {:received_response, ^correlation_id, {:error, :expired}}, @grace + 1000
    refute_receive {:received_response, ^correlation_id, {:ok, ^payload}}, @grace + 1000

    GenServer.stop(client)
    GenServer.stop(server)
  end
end

defmodule TestClient do
  use GenServer
  use ExRabbitMQ.RPC.Client

  @timeout 2000

  def start() do
    GenServer.start(__MODULE__, test_pid: self())
  end

  def init(test_pid: test_pid) do
    setup_client(:test_connection, %{test_pid: test_pid})
  end

  def test_request(client, payload, correlation_id) do
    GenServer.cast(client, {:test_request, payload, correlation_id})
  end

  def handle_cast({:test_request, payload, correlation_id}, %{test_pid: test_pid} = state) do
    queue = Application.get_env(:exrabbitmq, :test_session)[:queue]
    payload = Poison.encode!(payload)
    result = request(payload, "", queue, correlation_id: correlation_id, expiration: @timeout)
    send(test_pid, {:send_request, result})
    {:noreply, state}
  end

  def handle_response({:ok, payload}, correlation_id, %{test_pid: test_pid} = state) do
    parsed = Poison.decode!(payload, as: %Payload{})
    send(test_pid, {:received_response, correlation_id, {:ok, parsed}})
    {:noreply, state}
  end

  def handle_response(result, correlation_id, %{test_pid: test_pid} = state) do
    send(test_pid, {:received_response, correlation_id, result})
    {:noreply, state}
  end
end

defmodule TestServer do
  use GenServer
  use ExRabbitMQ.RPC.Server

  def start() do
    GenServer.start(__MODULE__, test_pid: self())
  end

  def init(test_pid: test_pid) do
    setup_server(:test_connection, :test_session, %{test_pid: test_pid})
  end

  def handle_request(bin_payload, metadata, state) do
    %{correlation_id: correlation_id} = metadata
    %{test_pid: test_pid} = state
    payload = %Payload{delay: delay} = Poison.decode!(bin_payload, as: %Payload{})
    send(test_pid, {:received_request, correlation_id, payload})

    if delay == 0 do
      # Echo back the payload.
      {:respond, bin_payload, state}
    else
      Process.send_after(self(), {:respond, metadata, bin_payload}, delay)
      {:noreply, state}
    end
  end

  def handle_info({:basic_consume_ok, _}, state) do
    {:noreply, state}
  end

  def handle_info({:respond, %{delivery_tag: tag} = metadata, payload}, state) do
    respond(payload, metadata)
    xrmq_basic_ack(tag, state)
    {:noreply, state}
  end
end
