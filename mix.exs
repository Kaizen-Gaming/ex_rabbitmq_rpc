defmodule ExRabbitMQ.RPC.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ex_rabbitmq_rpc,
      version: "2.0.0",
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
      # {:exrabbitmq, "~> 2.11"},
      {:exrabbitmq, github: "StoiximanServices/exrabbitmq", branch: "multiple_declarations"},
      {:credo, "~> 0.8", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 0.5", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.19", only: [:dev], runtime: false},
      {:poison, "~> 3.1", runtime: false}
    ]
  end
end
