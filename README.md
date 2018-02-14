# ExRabbitMQ.RPC

Provides behavior modules for creating RPC clients and servers through RabbitMQ.

![RPC Diagram](rpc_diagram.png)

Under the hood, uses an [`ExRabbitMQ.Consumer`](https://hexdocs.pm/exrabbitmq/ExRabbitMQ.Consumer.html) for configuring and consuming messages from RabbitMQ.

## Installation

The package can be installed by adding `ex_rabbitmq_rpc` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_rabbitmq_rpc, "<~ 1.0"}
  ]
end
```

## Documentation

To read the documentation you may run `mix docs` in a console and then browse the `doc` folder, or visit [hexdocs](https://hexdocs.pm/ex_rabbitmq_rpc).

## Testing

To run the tests, make sure you have access on the RabbitMQ service at `localhost`. You may configure the RabbitMQ service by editing the `config/test.exs` file.