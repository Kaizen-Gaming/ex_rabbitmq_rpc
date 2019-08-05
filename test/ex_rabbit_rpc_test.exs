defmodule ExRabbitMQ.RPCTest do
  use ExUnit.Case, async: false

  setup_all do
    {:ok, _pid} = ExRabbitMQ.Connection.Pool.Supervisor.start_link([])
    :ok
  end

  @grace 3_000

  test "client can request and get response from server" do
    delay = 0
    correlation_id = UUID.uuid4()

    {:ok, client} = TestClient.start()
    {:ok, server} = TestServer.start()

    assert_receive :connected, @grace
    assert_receive :connected, @grace

    :ok = TestClient.test_request(client, delay, correlation_id)

    assert_receive {:send_request, {:ok, ^correlation_id}}
    assert_receive {:received_request, ^correlation_id, ^delay}
    assert_receive {:received_response, ^correlation_id, {:ok, ^delay}}
    refute_receive {:received_response, ^correlation_id, {:error, :expired}}, @grace

    GenServer.stop(client)
    GenServer.stop(server)
  end

  test "request can expire" do
    delay = @grace
    correlation_id = UUID.uuid4()

    {:ok, client} = TestClient.start()
    {:ok, server} = TestServer.start()

    assert_receive :connected, @grace
    assert_receive :connected, @grace

    :ok = TestClient.test_request(client, delay, correlation_id)

    assert_receive {:send_request, {:ok, ^correlation_id}}
    assert_receive {:received_request, ^correlation_id, ^delay}
    assert_receive {:received_response, ^correlation_id, {:error, :expired}}, @grace + 1_000
    refute_receive {:received_response, ^correlation_id, {:ok, ^delay}}, @grace + 1_000

    GenServer.stop(client)
    GenServer.stop(server)
  end
end

defmodule TestClient do
  use GenServer
  use ExRabbitMQ.RPC.Client

  @timeout 2_000

  def start do
    GenServer.start(__MODULE__, test_pid: self())
  end

  @impl true
  def init(test_pid: test_pid) do
    setup_client(:test_connection, %{test_pid: test_pid})
  end

  def test_request(client, payload, correlation_id) do
    GenServer.cast(client, {:test_request, payload, correlation_id})
  end

  @impl true
  def handle_cast({:test_request, payload, correlation_id}, %{test_pid: test_pid} = state) do
    queue = Application.get_env(:exrabbitmq, :test_session)[:queue]
    payload = to_string(payload)
    result = request(payload, "", queue, correlation_id: correlation_id, expiration: @timeout)
    send(test_pid, {:send_request, result})
    {:noreply, state}
  end

  @impl true
  def handle_response({:ok, payload}, correlation_id, %{test_pid: test_pid} = state) do
    {parsed, _} = Integer.parse(payload)
    send(test_pid, {:received_response, correlation_id, {:ok, parsed}})
    {:noreply, state}
  end

  @impl true
  def handle_response(result, correlation_id, %{test_pid: test_pid} = state) do
    send(test_pid, {:received_response, correlation_id, result})
    {:noreply, state}
  end

  def xrmq_on_try_init_success(%{test_pid: test_pid} = state) do
    send(test_pid, :connected)

    state
  end
end

defmodule TestServer do
  use GenServer
  use ExRabbitMQ.RPC.Server

  def start do
    GenServer.start(__MODULE__, test_pid: self())
  end

  @impl true
  def init(test_pid: test_pid) do
    setup_server(:test_connection, :test_session, %{test_pid: test_pid})
  end

  @impl true
  def handle_request(bin_payload, metadata, state) do
    %{correlation_id: correlation_id} = metadata
    %{test_pid: test_pid} = state
    {delay, _} = Integer.parse(bin_payload)
    send(test_pid, {:received_request, correlation_id, delay})

    if delay == 0 do
      # Echo back the payload.
      {:respond, bin_payload, state}
    else
      Process.send_after(self(), {:respond, metadata, bin_payload}, delay)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:basic_consume_ok, _}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:respond, %{delivery_tag: tag} = metadata, payload}, state) do
    respond(payload, metadata)
    xrmq_basic_ack(tag, state)
    {:noreply, state}
  end

  def xrmq_on_try_init_success(%{test_pid: test_pid} = state) do
    send(test_pid, :connected)

    state
  end
end
