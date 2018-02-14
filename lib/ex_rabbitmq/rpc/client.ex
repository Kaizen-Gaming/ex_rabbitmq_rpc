defmodule ExRabbitMQ.RPC.Client do
  @moduledoc """
  *A behavior module for implementing a RabbitMQ RPC client with a `GenServer`.*

  It uses the `ExRabbitMQ.Consumer`, which in-turn uses the `AMQP` library to configure and consume messages from a
  queue that are actually the response messages of the requests. This queue is set as the `reply_to` header in the AMQP
  message so that the RPC server knows where to reply with a response message. Additionally, all request messages are
  "tagged" with a `correlation_id` which the RPC server also includes in the response message, so that the RPC client
  can be track and relate it.

  A typical implementation of this behavior is to call the `c:setup_client/2` on `GenServer.init/1` and then call the
  `c:request/4` for sending request messages. When the response message is received the `c:handle_response/3` will be
  invoked.
  Make sure that before starting a `ExRabbitMQ.RPC.Client` to already run in your supervision tree the
  `ExRabbitMQ.Connection.Supervisor`.

  **Example**

  ```elixir
  defmodule MyClient do

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
      {:noreply, state}line
    end

    def handle_response({:ok, payload}, correlation_id, state) do
      # Do some processing here...
      {:noreply, state}
    end

  end
  ```
  """

  @doc """
  Opens a RabbitMQ connection & channel and configures a default queue for receiving responses.

  Almost same as the `c:setup_client/3` but without any parameters for configuring the queue. Instead it will configure
  a temporary queue on RabbitMQ just for receiving message, that will be deleted when the channel is down.

  The configuration of the queue will be:
  ```elixir
  %QueueConfig{
    queue: "rpc.gen-" <> UUID.uuid4(),
    queue_opts: [exclusive: true, auto_delete: true],
    consume_opts: [no_ack: false]
  }
  ```

  *For more information about the usage, also check the documentation of the function `c:setup_client/3`.*
  """
  @callback setup_client(connection_config :: connection, state :: term) ::
    {:ok, new_state} |
    {:error, reason :: term, new_state}
    when new_state: term, connection: atom | %ExRabbitMQ.Connection.Config{}

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

  The parameter `connection_config` can also be set to the struct `ExRabbitMQ.Connection.Config` which allows
  to programatically configure the connection without config.exs.

  The parameter `state` is the state of the `GenServer` process.

  The optional parameter `opts` provides additional options for setting up the RabbitMQ client.
  The available options are:

  * `:queue` - specifies a custom Queue configuration. If set to an atom, the configuration will be loaded from the
    application's config.exs under the app key :exrabbitmq,
    eg. if the value is set to `:default_queue`, then the config.exs should have configuration like the following:

    ```elixir
    config :exrabbitmq, :default_queue,
      queue: "test_queue",
      queue_opts: [durable: true],
      consume_opts: [no_ack: true]
    ```

    If not set, then a temporary queue on RabbitMQ just for receiving message, that will be deleted when the channel
    is down. The configuration of the queue will be:

    ```elixir
    %QueueConfig{
      queue: "rpc.gen-" <> UUID.uuid4(),
      queue_opts: [exclusive: true, auto_delete: true],
      consume_opts: [no_ack: false]
    }
    ```

  * `:queue_prefix` - allows to specify the prefix of the generated queue name, which by default is `rpc.gen-`.
    If the `:queue` option is set, this setting will be ignored.

  The return of the function can be `{:ok, state}` when the consumer has been successfully registered or on error the
  tuple `{:error, reason, state}`.

  *For more information about the connection & queue configuration, please check the documentation of the function
  `ExRabbitMQ.Consumer.xrmq_init/3`.*
  """
  @callback setup_client(connection_config :: connection, state :: term, opts :: keyword) ::
    {:ok, new_state} |
    {:error, reason :: term, new_state}
    when new_state: term, connection: atom | %ExRabbitMQ.Connection.Config{}

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
                  with `c:setup_client/2` or `c:setup_client/3`,
  * `:timestamp` - if not specified, will be set to the current time,
  * `:expiration` - if not specified, will be set to 5000ms. For no expiration, it needs to be set to a value that
                    is less or equal than zero.

  The return value can be:
  * `{:ok, correlation_id}` - the request has been published successfully. The `correlation_id` is an id for this
                              request, that the RPC server will include in the response message, and this process can
                              relate it when receives this response,
  * `{:error, reason}` - the request has failed to be published with the returned `reason`.

  """
  @callback request(payload :: binary, exchange :: String.t, routing_key :: String.t, opts :: keyword) ::
    {:ok, correlation_id :: String.t} |
    {:error, reason :: term}

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
  @callback handle_response(response :: response, correlation_id :: String.t, state :: term) ::
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason :: term, new_state}
    when new_state: term, response: {:ok, payload :: String.t} | {:error, reason :: term}

  defmacro __using__(_) do
    quote location: :keep do

      @behaviour ExRabbitMQ.RPC.Client

      use ExRabbitMQ.Consumer, GenServer

      alias AMQP.Basic
      alias ExRabbitMQ.Consumer.QueueConfig

      @doc false
      def setup_client(connection_config, state, opts \\ []) do
        queue_prefix = Keyword.get(opts, :queue_prefix, "rpc.gen-")
        queue_config = opts[:queue] || %QueueConfig{
          queue: queue_prefix <> UUID.uuid4(),
          queue_opts: [exclusive: true, auto_delete: true],
          consume_opts: [no_ack: false]
        }
        xrmq_init(connection_config, queue_config, state)
      end

      @doc false
      def request(payload, exchange, routing_key, opts \\ []) do
        expiration = get_expiration(opts[:expiration])
        correlation_id = get_correlation_id(opts[:correlation_id])
        with \
          {:ok, channel} <- get_channel(),
          {:ok, reply_to} <- get_reply_to_queue(),
          opts <- get_publish_options(opts, correlation_id, reply_to, expiration),
          :ok <- Basic.publish(channel, exchange, routing_key, payload, opts),
          _ <- setup_expiration(correlation_id, expiration)
        do
          {:ok, correlation_id}
        else
          {:error, reason} -> {:error, reason}
          error -> {:error, error}
        end
      end

      @doc false
      # Receive a message when the reply_to queue has been registered for consuming.
      def handle_info({:basic_consume_ok, _}, state) do
        {:noreply, state}
      end

      @doc false
      # Receive the message that was send by `setup_expiration/2` that informs the process that
      # the request message has expired on RabbitMQ.
      def handle_info({:expired, correlation_id}, state) do
        case remove_expiration_id(correlation_id) do
          {:ok, _} -> handle_response({:error, :expired}, correlation_id, state)
          {:error, :not_found} -> {:noreply, state}
        end
      end

      @doc false
      # Receive the response message and calls the `c:handle_response/3` for further processing.
      def xrmq_basic_deliver(payload, %{correlation_id: correlation_id}, state) do
        case remove_expiration_id(correlation_id) do
          {:ok, ref} ->
            Process.cancel_timer(ref)
            handle_response({:ok, payload}, correlation_id, state)
          _ -> {:noreply, state}
        end
      end

      # Gets the channel information for the process dictionary.
      defp get_channel do
        case xrmq_get_channel_info() do
          {channel, _} when channel != nil -> {:ok, channel}
          _ -> {:error, :no_channel}
        end
      end

      # Returns the queue name for receiving the replies.
      defp get_reply_to_queue do
        case xrmq_get_queue_config() do
          %{queue: queue} when queue != nil or queue != "" -> {:ok, queue}
          _ -> {:error, :no_queue}
        end
      end

      # Returns the options for publishing.
      defp get_publish_options(opts, correlation_id, reply_to, expiration) do
        opts
        |> Keyword.put(:correlation_id, correlation_id)
        |> Keyword.put(:reply_to, reply_to)
        |> Keyword.put(:expiration, if(expiration > 0, do: to_string(expiration), else: :undefined))
        |> Keyword.put_new_lazy(:timestamp, fn -> DateTime.utc_now() |> DateTime.to_unix(:millisecond) end)
      end

      # Returns a default auto-generated correlation_id, if not specified.
      defp get_correlation_id(nil), do: "req.gen-" <> UUID.uuid4()
      defp get_correlation_id(value), do: value

      # Returns a expiration time for the request, if not specified.
      defp get_expiration(value) when is_number(value) and value < 1, do: 0
      defp get_expiration(value) when is_number(value), do: value
      defp get_expiration(_), do: 5000

      # Sends a message to this process after `expiration` milliseconds, so that we get notified when the message
      # on RabbitMQ has also expired.
      defp setup_expiration(correlation_id, expiration) when expiration > 0 do
        ref = Process.send_after(self(), {:expired, correlation_id}, expiration)
        get_expirations()
        |> Map.put(correlation_id, ref)
        |> save_expirations()
      end
      defp setup_expiration(_correlation_id, _expiration), do: :ignore

      @spec get_expirations() :: map
      defp get_expirations, do: Process.get(:rpc_expirations, Map.new)

      @spec save_expirations(map) :: nil
      defp save_expirations(%{} = map), do: Process.put(:rpc_expirations, map)

      @spec remove_expiration_id(String.t) :: {:ok, String.t} | {:error, :not_found}
      defp remove_expiration_id(correlation_id) do
        expirations = get_expirations()
        case expirations[correlation_id] do
          nil -> {:error, :not_found}
          ref when is_reference(ref) ->
            expirations
            |> Map.delete(correlation_id)
            |> save_expirations()
            {:ok, ref}
        end
      end

    end
  end

end
