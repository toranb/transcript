defmodule Transcript.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Nx.default_backend(EXLA.Backend)

    {:ok, whisper} = Bumblebee.load_model({:hf, "openai/whisper-tiny"})
    {:ok, featurizer} = Bumblebee.load_featurizer({:hf, "openai/whisper-tiny"})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, "openai/whisper-tiny"})
    {:ok, generation_config} = Bumblebee.load_generation_config({:hf, "openai/whisper-tiny"})

    serving =
      Bumblebee.Audio.speech_to_text(whisper, featurizer, tokenizer, generation_config,
        defn_options: [compiler: EXLA]
      )

    children = [
      TranscriptWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:transcript, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Transcript.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Transcript.Finch},
      {Nx.Serving, name: WhisperServing, serving: serving},
      # Start a worker by calling: Transcript.Worker.start_link(arg)
      # {Transcript.Worker, arg},
      # Start to serve requests, typically the last entry
      TranscriptWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Transcript.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TranscriptWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
