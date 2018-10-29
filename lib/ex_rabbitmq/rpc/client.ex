defmodule ExRabbitMQ.RPC.Client do
  @moduledoc """
  *A behavior module for implementing a RabbitMQ RPC client with a `GenServer`.*

  It uses the `ExRabbitMQ.Consumer`, which in-turn uses the `AMQP` library to configure and consume messages from a
  queue that are actually the response messages of the requests. This queue is set as the `reply_to` header in the AMQP
  message so that the RPC server knows where to reply with a response message. Additionally, all request messages are
  "tagged" with a `correlation_id` which the RPC server also includes in the response message, so that the RPC client
  can be track and relate it.

  A typical implementation of this behavior is to call the `c:setup_client/3` on `GenServer.init/1` and then call the
  `c:request/4` for sending request messages. When the response message is received the `c:handle_response/3` will be
  invoked.
  Make sure that before starting a `ExRabbitMQ.RPC.Client` to already run in your supervision tree the
  `ExRabbitMQ.Connection.Supervisor`.

  **Example**

  ```elixir
  defmodule MyClient do
    @moduledoc false

    use GenServer
    use ExRabbitMQ.RPC.Client

    def start_link(args) do
      GenServer.start_link(__MODULE__, args, [])
    end

    def init(_) do
      {:ok, state} = setup_client(:connection, %{})
      {:ok, state}
    end

    def request_something(client, queue, value) do
      GenServer.cast(client, {:request_something, queue, value})
    end

    def handle_cast({:request_something, queue, value}, state) do
      payload = Poison.encode!(value)
      {:ok, _correlation_id} = request(payload, "", queue)
      {:noreply, state}
    end

    def handle_response({:ok, payload}, correlation_id, state) do
      # Do some processing here...
      {:noreply, state}
    end
  end
  ```
  """

  @type state :: term

  @type response :: {:ok, payload :: String.t()} | {:error, reason :: term}

  @type connection :: atom | %ExRabbitMQ.Config.Connection{}

  @type result :: {:ok, state} | {:error, reason :: term, state}

  @type request_result :: {:ok, correlation_id :: String.t()} | {:error, reason :: term}

  @type response_result ::
          {:noreply, state}
          | {:noreply, state, timeout | :hibernate}
          | {:stop, reason :: term, state}

  @doc """
  Opens a RabbitMQ connection & channel and configures the queue for receiving responses.

  This function calls the function `ExRabbitMQ.Consumer.xrmq_init/3` for creating a new RabbitMQ connection &
  channel and configure the exchange & queue for consuming incoming response messages. This queue will be set in the
  `reply_to` header of the AMQP message and will be used by the RPC server to reply back with a response message.
  This function is usually called on `GenServer.init/1` callback.

  ### Parameters

  The parameter `connection_config` specifies the configuration of the RabbitMQ connection. If set to an atom,
  the configuration will be loaded from the application's config.exs under the app key :exrabbitmq,
  eg. if the value is set to `:default_connection`, then the config.exs should have configuration like the following:

  ```elixir
  config :exrabbitmq, :default_connection,
    username: "guest",
    password: "guest",
    host: "localhost",
    port: 5672
  ```

  The parameter `connection_config` can also be set to the struct `ExRabbitMQ.Config.Connection` which allows
  to programatically configure the connection without config.exs.

  The parameter `state` is the state of the `GenServer` process.

  The optional parameter `opts` provides additional options for setting up the RabbitMQ client.
  The available options are:

  * `:session_config` - specifies a custom configuration for setting up the queue.
    If set to an atom, the configuration will be loaded from the application's config.exs under the app key :exrabbitmq,
    eg. if the value is set to `:my_rpc_queue`, then the config.exs should have configuration like the following:

    ```elixir
    config :exrabbitmq, :my_rpc_queue,
      queue: "my_rpc_queue",
      consume_opts: [no_ack: true],
      declarations: [
        {:queue, [name: "my_rpc_queue", opts: [durable: true]]}
      ]
    ```

    If set to a `ExRabbitMQ.Consumer.SessionConfig` struct, then it will use it as-is.

    If not set, then a temporary queue will be declared on RabbitMQ just for receiving messages, 
    which will be deleted when the channel is down. The configuration will be:

    ```elixir
    queue_name = queue_prefix <> UUID.uuid4()

    %ExRabbitMQ.Config.Session{
      queue: queue_name,
      consume_opts: [no_ack: false],
      declarations: [
        {:queue, %ExRabbitMQ.Config.Queue{
          name: queue_name,
          opts: [exclusive: true, auto_delete: true]
        }}
      ]
    }
    ```

  * `:queue_prefix` - allows to specify the prefix of the generated queue name, which by default is `rpc.gen-`.
    If the `:session` option is set, this setting will be ignored.

  The return of the function can be `{:ok, state}` when the consumer has been successfully registered or on error the
  tuple `{:error, reason, state}`.

  *For more information about the connection & queue configuration, please check the documentation of the function
  `ExRabbitMQ.Consumer.xrmq_init/3`.*
  """
  @callback setup_client(connection_config :: connection, state, opts :: keyword) :: result

  @doc """
  Publishes a request message with `payload` to specified exchange and queue.

  This function will publish a message on a queue that a RPC server is consuming, which we will receive the response
  message through the `c:handle_response/3` callback. This function **must** be called from the `ExRabbitMQ.RPC.Client`
  process, as it needs the process's dictionary which contain the connection & channel information.

  ### Parameters

  The parameter `payload` is the payload of the request message to be sent to the RPC server.

  The parameter `exchange` is the RabbitMQ exchange to use for routing this message.

  The parameter `queue` is the RabbitMQ queue to deliver this message. This queue must be the queue that an RPC server
  is consuming.

  The parameter `opts` is a keyword list with the publishing options. The publish options are the same as in
  `AMQP.Basic.publish/5` but with a few changes:

  * `:correlation_id` - if not specified, will be set to an auto-generated one (using `UUID.uuid4/0`),
  * `:reply_to` - cannot be overrided and will be always set as the queue name as configured
                  with `c:setup_client/3`,
  * `:timestamp` - if not specified, will be set to the current time,
  * `:expiration` - if not specified, will be set to 5000ms. For no expiration, it needs to be set to a value that
                    is less or equal than zero.

  The return value can be:
  * `{:ok, correlation_id}` - the request has been published successfully. The `correlation_id` is an id for this
                              request, that the RPC server will include in the response message, and this process can
                              relate it when receives this response,
  * `{:error, reason}` - the request has failed to be published with the returned `reason`.

  """
  @callback request(
              payload :: binary,
              exchange :: String.t(),
              routing_key :: String.t(),
              opts :: keyword
            ) :: request_result

  @doc """
  Invoked when a message has been received from RabbitMQ which is a response message from the RPC server for a request
  we previously did.

  ### Parameters

  The parameter `response` has the result of the request and the can take the following values:
  * `{:ok, payload}` - the RPC server has replied with a response message for our request.
  * `{:error, reason}` - when there was an error with the response of the request. If the `reason` has the value
                         `:expired`, then the `:expiration` value in the request message has been exceeded, meaning
                         that the RPC server didn't respond within this time.

  The parameter `correlation_id` is the id of the request that this response is related to. This value was set
  previously with the call of the `c:request/4` function and the RPC server returned it back with the response message.

  The parameter `state` is the state of the `GenServer` process.

  This callback should return a value, as in `GenServer.handle_info/2`.
  """
  @callback handle_response(response :: response, correlation_id :: String.t(), state) ::
              response_result

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour ExRabbitMQ.RPC.Client

      alias ExRabbitMQ.RPC.Client.{ExpirationHandler, Options, RequestTracking}

      use ExRabbitMQ.Consumer, GenServer

      @doc false
      def setup_client(connection_config, state, opts \\ []) do
        session_config = Options.get_session_config(opts)

        xrmq_init(connection_config, session_config, state)
      end

      @doc false
      def request(payload, exchange, routing_key, opts \\ []) do
        expiration = Options.get_expiration(opts)
        correlation_id = Options.get_correlation_id(opts)
        from = Options.get_call_from(opts)

        with {:ok, channel} <- get_channel(),
             {:ok, reply_to} <- get_reply_to_queue(),
             opts <- Options.get_publish_options(opts, correlation_id, reply_to, expiration),
             :ok <- AMQP.Basic.publish(channel, exchange, routing_key, payload, opts),
             :ok <- ExpirationHandler.set(correlation_id, expiration),
             :ok <- RequestTracking.set(correlation_id, from) do
          {:ok, correlation_id}
        else
          {:error, reason} -> {:error, reason}
          error -> {:error, error}
        end
      end

      @doc false
      def request_sync(client, payload, exchange, routing_key, opts \\ []) do
        expiration = Options.get_expiration(opts)
        message = {payload, exchange, routing_key, opts}

        GenServer.call(client, {:rpc_request_sync, message}, expiration + 1000)
      end

      @doc false
      # Receive a message when the reply_to queue has been registered for consuming.
      def handle_info({:basic_consume_ok, _}, state) do
        {:noreply, state}
      end

      @doc false
      # Receive the message that was send by `ExRabbitMQ.RPC.Client.ExpirationHandler.set/2` and inform the calling
      # process the request message has expired on RabbitMQ (either nobody consumed the message or the consumer could
      # not reply within the request timeout).
      def handle_info({:expired, correlation_id}, state) do
        do_handle_response({:error, :expired}, correlation_id, state)
      end

      @doc false
      def handle_call({:rpc_request_sync, message}, from, state) do
        {payload, exchange, routing_key, opts} = message
        opts = Options.set_call_from(opts, from)

        with {:ok, _correlation_id} <- request(payload, exchange, routing_key, opts) do
          {:noreply, state}
        else
          error -> {:reply, error, state}
        end
      end

      @doc false
      # Receive the response message and calls the `c:handle_response/3` for further processing.
      # If the response is related with a synchronous request, then reply to that process instead.
      def xrmq_basic_deliver(payload, %{correlation_id: correlation_id}, state) do
        do_handle_response({:ok, payload}, correlation_id, state)
      end

      # Gets the channel information for the process dictionary.
      defp get_channel do
        case ExRabbitMQ.State.get_channel_info() do
          {channel, _} when channel != nil -> {:ok, channel}
          _ -> {:error, :no_channel}
        end
      end

      # Returns the queue name for receiving the replies.
      defp get_reply_to_queue do
        case ExRabbitMQ.State.get_session_config() do
          %{queue: queue} when queue != nil or queue != "" -> {:ok, queue}
          _ -> {:error, :no_queue}
        end
      end

      defp do_handle_response(result, correlation_id, state) do
        with :ok <- ExpirationHandler.cancel(correlation_id),
             {:ok, from} <- RequestTracking.get_delete(correlation_id) do
          GenServer.reply(from, result)
          {:noreply, state}
        else
          {:error, :no_request_tracking} ->
            handle_response(result, correlation_id, state)

          _ ->
            {:noreply, state}
        end
      end
    end
  end
end
