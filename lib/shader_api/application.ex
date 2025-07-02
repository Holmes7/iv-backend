defmodule ShaderApi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ShaderApiWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:shader_api, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ShaderApi.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: ShaderApi.Finch},
      # Start a worker by calling: ShaderApi.Worker.start_link(arg)
      # {ShaderApi.Worker, arg},
      # Start to serve requests, typically the last entry
      ShaderApiWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ShaderApi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ShaderApiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
