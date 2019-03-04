defmodule ExRabbitMQ.RPC.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ex_rabbitmq_rpc,
      version: "2.0.1",
      elixir: "~> 1.7",
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
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0.0-rc.4", only: :dev, runtime: false},
      {:ex_doc, "~> 0.19.3", only: :dev, runtime: false},
      {:exrabbitmq, github: "StoiximanServices/exrabbitmq", branch: "multiple_declarations"},
      {:uuid, "~> 1.1"}
    ]
  end
end
