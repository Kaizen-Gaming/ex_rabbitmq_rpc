defmodule ExRabbitMQ.RPC.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ex_rabbitmq_rpc,
      version: "1.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "ExRabbitMQ RPC",
      source_url: "https://github.com/StoiximanServices/ex_rabbitmq_rpc",
      docs: [logo: "logo.png"]
    ]
  end

  def application do
    []
  end

  defp deps do
    [
      {:uuid, "~> 1.1"},
      {:exrabbitmq, "~> 2.11"},
      {:credo, "~> 0.8", runtime: false},
      {:dialyxir, "~> 0.5", runtime: false},
      {:ex_doc, "~> 0.19", runtime: false, override: true},
      {:poison, "~> 3.1", only: :test}
    ]
  end
end
