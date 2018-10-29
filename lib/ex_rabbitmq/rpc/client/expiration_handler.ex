defmodule ExRabbitMQ.RPC.Client.ExpirationHandler do
  @moduledoc false

  @key __MODULE__

  @doc """
  Sets the expiration for this request.

  It will schedule to send the message `{:expired, correlation_id}` to the `ExRabbitMQ.RPC.Client`
  process after `expiration` milliseconds, so that we get notified when the request message
  on RabbitMQ has also expired.
  """
  @spec set(correlation_id :: String.t(), expiration :: number) :: :ok
  def set(correlation_id, expiration) when expiration > 0 do
    ref = Process.send_after(self(), {:expired, correlation_id}, expiration)
    expirations = process_get()
    add_correlation_id(expirations, correlation_id, ref)

    :ok
  end

  def set(_correlation_id, _expiration), do: :ok

  @doc """
  Cancels the scheduled `{:expired, correlation_id}` message for the specified `correlation_id`.

  This function should called when the `ExRabbitMQ.RPC.Client` process receives the response
  of the request.
  """
  @spec cancel(String.t()) :: {:ok, String.t()} | {:error, :no_expiration}
  def cancel(correlation_id) do
    case process_get() do
      %{^correlation_id => ref} = expirations ->
        remove_correlation_id(expirations, correlation_id)
        Process.cancel_timer(ref)

        :ok

      _ ->
        {:error, :no_expiration}
    end
  end

  defp process_get, do: Process.get(@key, Map.new())

  defp process_put(%{} = map), do: Process.put(@key, map)

  defp add_correlation_id(expirations, correlation_id, ref) do
    expirations
    |> Map.put(correlation_id, ref)
    |> process_put()
  end

  defp remove_correlation_id(expirations, correlation_id) do
    expirations
    |> Map.delete(correlation_id)
    |> process_put()
  end
end
