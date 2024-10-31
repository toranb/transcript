defmodule Transcript.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Nx.default_backend(EXLA.Backend)

    repository_id = {:hf, "openai/whisper-large-v3-turbo"}

    {:ok, model_info} = Bumblebee.load_model(repository_id, type: :f16)
    {:ok, featurizer} = Bumblebee.load_featurizer(repository_id)
    {:ok, tokenizer} = Bumblebee.load_tokenizer(repository_id)

    {:ok, generation_config} =
      Bumblebee.load_generation_config(repository_id)

    serving =
      Bumblebee.Audio.speech_to_text_whisper(
        model_info,
        featurizer,
        tokenizer,
        generation_config,
        compile: [batch_size: 1],
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
