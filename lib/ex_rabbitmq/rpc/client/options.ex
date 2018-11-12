defmodule ExRabbitMQ.RPC.Client.Options do
  @moduledoc false

  alias ExRabbitMQ.Config.{Queue, Session}

  import UUID, only: [uuid4: 0]

  @default_queue_prefix "rpc.gen-"

  @default_correlation_prefix "req.gen-"

  @default_expiration 5000

  @doc """
  Returns the `ExRabbitMQ.Config.Session` configuration for the `reply-to` queue.
  """
  def get_session_config(opts) do
    case Keyword.get(opts, :session, nil) do
      nil ->
        get_default_session_config(opts)

      session ->
        session
    end
  end

  # Returns the default session configuration that declares the `reply-to` queue
  # plus any extra declarations from the :declarations option.
  defp get_default_session_config(opts) do
    queue_prefix = Keyword.get(opts, :queue_prefix, @default_queue_prefix)
    queue_name = queue_prefix <> uuid4()

    declarations = [
      {:queue,
       %Queue{
         name: queue_name,
         opts: [exclusive: true, auto_delete: true]
       }}
    ]

    %Session{
      queue: queue_name,
      consume_opts: [no_ack: false],
      declarations: get_extra_declarations(opts) ++ declarations
    }
  end

  # Returns a list with any extra declarations that were defined in the `:declaration` option
  defp get_extra_declarations(opts) do
    case Keyword.get(opts, :declarations, []) do
      session_config_key when is_atom(session_config_key) ->
        %{declarations: declarations} = Session.get(session_config_key)
        declarations

      declarations when is_list(declarations) ->
        declarations
    end
  end

  @doc """
  Returns the `AMQP.Basic.publish` options.

  Sets the options for `correlation_id`, `reply_to` and `expiration` as specified in the arguments.
  Also set the `timestamp` to the current time.
  """
  def get_publish_options(opts, correlation_id, reply_to, expiration) do
    expiration = if expiration > 0, do: to_string(expiration), else: :undefined

    opts
    |> Keyword.put(:correlation_id, correlation_id)
    |> Keyword.put(:reply_to, reply_to)
    |> Keyword.put(:expiration, expiration)
    |> Keyword.put_new_lazy(:timestamp, &get_unix_now/0)
  end

  defp get_unix_now, do: DateTime.utc_now() |> DateTime.to_unix(:millisecond)

  @doc """
  Returns the correlation_id for the request.

  Defaults to a random generated one.
  """
  def get_correlation_id(opts), do: do_get_correlation_id(opts[:correlation_id])

  defp do_get_correlation_id(nil), do: @default_correlation_prefix <> uuid4()
  defp do_get_correlation_id(value), do: value

  @doc """
  Returns the expiration time in milliseconds for the request.

  Defaults to `5000` milliseconds.
  """
  def get_expiration(opts), do: do_get_expiration(opts[:expiration])

  defp do_get_expiration(value) when is_number(value) and value < 1, do: 0
  defp do_get_expiration(value) when is_number(value), do: value
  defp do_get_expiration(_), do: @default_expiration

  @doc """
  Returns the `from` process that the response should be replied to.

  Defaults to `nil`.
  """
  def get_call_from(opts), do: do_get_call_from(opts[:call_from])

  defp do_get_call_from({pid, _tag} = from) when is_pid(pid), do: from
  defp do_get_call_from(_), do: nil

  @doc """
  Sets in the options the `from` process that the response should be replied to.
  """
  def set_call_from(opts, from), do: Keyword.put(opts, :call_from, from)
end
