defmodule ExRabbitMQ.RPC.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ex_rabbitmq_rpc,
      version: "2.2.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() not in [:dev, :test],
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
      {:credo, "~> 1.1", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0.0-rc.6", only: :dev, runtime: false},
      {:ex_doc, "~> 0.20.2", only: :dev, runtime: false},
      {:exrabbitmq, github: "StoiximanServices/exrabbitmq", tag: "v3.4.0"},
      {:uuid, "~> 1.1"}
    ]
  end
end
