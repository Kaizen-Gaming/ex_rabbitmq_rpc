defmodule ExRabbitMQ.RPC.Server do
  @moduledoc """
  *A behavior module for implementing a RabbitMQ RPC server with a `GenServer`.*

  It uses the `ExRabbitMQ.Consumer`, which in-turn uses the `AMQP` library to configure and consume messages.
  Additionally this module offers a way to receive requests and send back responses easily.

  A typical implementation of this behavior is to call the `c:setup_server/3` on `GenServer.init/1` and
  implement the `c:handle_request/3` for processing requests and responding back. When the application needs to
  respond back, the functions `c:respond/2` or `c:respond/3` can be called to achieve this.
  Make sure that before starting a `ExRabbitMQ.RPC.Server` to already run in your supervision tree the
  `ExRabbitMQ.Connection.Supervisor`.

  **Example**

  ```elixir
  defmodule MyServer do

    use GenServer
    use ExRabbitMQ.RPC.Server

    def start_link(args) do
      GenServer.start_link(__MODULE__, args, [])
    end

    def init(_) do
      {:ok, state} = setup_server(:connection, :queue, %{})
      {:ok, state}
    end

    def handle_request(payload, _metadata, state) do
      response = do_process_request(payload)
      {:respond, response, state}
    end

    # On consume success, AMQP will send this message to our process.
    def handle_info({:basic_consume_ok, _}, state) do
      {:noreply, state}
    end

  end
  ```
  """

  @doc """
  Opens a RabbitMQ connection & channel and configures the queue for receiving requests.

  This function calls the function `ExRabbitMQ.Consumer.xrmq_init/3` for creating a new RabbitMQ connection &
  channel and configure the exchange & queue for consuming incoming requests.
  This function is usually called on `GenServer.init/1` callback.

  ### Parameters

  The parameter `connection_config` specifies the configuration of the RabbitMQ connection. If set to an atom,
  the configuration will be loaded from the application's config.exs under the app key `:exrabbitmq`,
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

  The parameter `queue_config` specifies the configuration of the RabbitMQ queue to consume. If set to an atom,
  the configuration will be loaded from the application's config.exs under the app key :exrabbitmq,
  eg. if the value is set to `:default_queue`, then the config.exs should have configuration like the following:

  ```elixir
  config :exrabbitmq, :default_queue,
    queue: "test_queue",
    queue_opts: [durable: true],
    consume_opts: [no_ack: true]
  ```

  The parameter `connection_config` can also be set to the struct `ExRabbitMQ.Consumer.QueueConfig` which allows
  to programatically configure the queue without config.exs.
  Please note that the configuration above will only declare the queue and start consuming it. For further
  configuration such as exchange declare, queue bind and QOS setup, you need to override the `ExRabbitMQ` functions
  `ExRabbitMQ.Consumer.xrmq_channel_setup/2` and `ExRabbitMQ.Consumer.xrmq_queue_setup/3`.

  The parameter `state` is the state of the `GenServer` process.

  The return value can be `{:ok, state}` when the consumer has been successfully registered or on error the tuple
  `{:error, reason, state}`.

  *For more information about the usage, also check the documentation of the function
  `ExRabbitMQ.Consumer.xrmq_init/3`.*
  """
  @callback setup_server(
              connection_config :: connection,
              session_config :: session,
              state :: term
            ) ::
              {:ok, new_state}
              | {:error, reason :: term, new_state}
            when new_state: term,
                 connection: atom | %ExRabbitMQ.Config.Connection{},
                 session: atom | %ExRabbitMQ.Config.Session{}

  @doc """
  Responds to a request that was received through the `c:handle_request/3` callback.

  This function will publish a message back to the origin app of the request through RabbitMQ. It uses the metadata
  from the request message, the `reply_to` and `correlation_id` headers to route the response back. Additionally,
  the function **must** be called from the `ExRabbitMQ.RPC.Server` process, as it needs the process's dictionary
  which contain the connection & channel information.

  ### Parameters

  The parameter `payload` is the payload of the response to send back to the origin of the request,

  The parameter `metadata` if the metadata of the request message from which will use the the `reply_to` and
  `correlation_id` headers.

  The parameter `state` is the state of the `GenServer` process.

  The return value can be:
  * `:ok` - when the response has been send successfully,
  * `{:error, reason}` - then the response has failed to be send with the returned `reason`.
  """
  @callback respond(
              payload :: binary,
              metadata :: %{reply_to: String.t(), correlation_id: String.t()}
            ) ::
              :ok
              | {:error, reason :: term}

  @doc """
  Responds to a request that was received through the `c:handle_request/3` callback.

  Same as `respond/2` but with different parameters. The `metadata` parameter has been replaced with the
  `routing_key` and `correlation_id`.

  ### Parameters

  The parameter `routing_key` is the queue name to publish the message. This parameter is required and should never
  be nil or empty string.

  The parameter `correlation_id` is the correlation_id of the request message that we responding to.

  *For more information about the usage, also check the documentation of the function `respond/2`.*
  """
  @callback respond(payload :: binary, routing_key :: String.t(), correlation_id :: String.t()) ::
              :ok
              | {:error, reason :: term}

  @doc """
  Invoked when a message has been received from RabbitMQ and should be processed and reply with a response
  by your implementation of the `ExRabbitMQ.RPC.Server`.

  ### Parameters

  The parameter `payload` `payload` contains the message content.

  The parameter `metadata` contains all the metadata set when the message was published or any additional info
  set by the broker.

  The parameter `state` is the state of the `GenServer` process.

  The return values of this callback can be:
  * `{:respond, response, new_state}` - Will respond (publish) back to the origin of the request with a message with
    the `response` payload and will acknowledge the message on broker.
  * `{:ack, new_state}` - Will not respond back but will acknowledge the message on broker.
  * `{:reject, new_state}` - Will not respond back and will reject the message on broker.
  * Any other value will be passed as the return value of the `GenServer.handle_info/2`. In this case, no response will
    be send back or acknowledge or reject the message, and needs to be handled by the implementation. If the response
    needs to be done at later time, use the `respond/2` or `respond/3` for doing that.
  """
  @callback handle_request(payload :: binary, metadata :: map, state :: term) ::
              {:respond, response :: binary, new_state}
              | {:ack, new_state}
              | {:reject, new_state}
              | {:noreply, new_state}
              | {:noreply, new_state, timeout | :hibernate}
              | {:stop, reason :: term, new_state}
            when new_state: term

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour ExRabbitMQ.RPC.Server

      use ExRabbitMQ.Consumer, GenServer

      alias AMQP.Basic
      alias ExRabbitMQ.State

      @doc false
      def setup_server(connection_config, session_config, state) do
        xrmq_init(connection_config, session_config, state)
      end

      @doc false
      def respond(payload, metadata) do
        respond(payload, metadata[:reply_to], metadata[:correlation_id])
      end

      @doc false
      def respond(_payload, reply_to, _correlation_id) when is_nil(reply_to) or reply_to == "" do
        {:error, :no_reply_to}
      end

      @doc false
      def respond(payload, reply_to, correlation_id) do
        opts = [
          correlation_id: correlation_id || :undefined,
          timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
        ]

        with {:ok, channel} <- get_channel(),
             :ok <- Basic.publish(channel, "", reply_to, payload, opts) do
          :ok
        else
          {:error, reason} -> {:error, reason}
          error -> {:error, error}
        end
      end

      @doc false
      # Receives the request message and calls the `c:handle_request/3` for further processing.
      def xrmq_basic_deliver(payload, %{delivery_tag: delivery_tag} = metadata, state) do
        case handle_request(payload, metadata, state) do
          {:respond, response, state} ->
            respond(response, metadata)
            xrmq_basic_ack(delivery_tag, state)
            {:noreply, state}

          {:ack, state} ->
            xrmq_basic_ack(delivery_tag, state)
            {:noreply, state}

          {:reject, state} ->
            xrmq_basic_reject(delivery_tag, state)
            {:noreply, state}

          other ->
            other
        end
      end

      # Gets the channel information for the process dictionary.
      defp get_channel do
        case State.get_channel_info() do
          {channel, _} when channel != nil -> {:ok, channel}
          _ -> {:error, :no_channel}
        end
      end
    end
  end
end
