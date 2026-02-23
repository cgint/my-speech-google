defmodule SttPlayground.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        SttPlaygroundWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:stt_playground, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: SttPlayground.PubSub}
      ] ++
        maybe_http_client_children() ++
        maybe_stt_provider_child() ++
        maybe_tts_provider_child() ++
        [
          # Start to serve requests, typically the last entry
          SttPlaygroundWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SttPlayground.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SttPlaygroundWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp maybe_stt_provider_child do
    start? =
      Application.get_env(
        :stt_playground,
        :start_stt_provider,
        Application.get_env(:stt_playground, :start_python_port, true)
      )

    if start? do
      provider = stt_provider_module()
      opts = stt_provider_opts(provider)
      [{provider, opts}]
    else
      []
    end
  end

  defp maybe_tts_provider_child do
    start? =
      Application.get_env(
        :stt_playground,
        :start_tts_provider,
        Application.get_env(:stt_playground, :start_tts_port, true)
      )

    if start? do
      provider = tts_provider_module()
      opts = tts_provider_opts(provider)
      [{provider, opts}]
    else
      []
    end
  end

  defp maybe_http_client_children do
    start_tts? =
      Application.get_env(
        :stt_playground,
        :start_tts_provider,
        Application.get_env(:stt_playground, :start_tts_port, true)
      )

    if start_tts? and tts_provider_module() == SttPlayground.TTS.GoogleHttp do
      [{Finch, name: SttPlayground.Finch}]
    else
      []
    end
  end

  defp stt_provider_module do
    Application.get_env(:stt_playground, :stt_provider, SttPlayground.STT.PythonPort)
  end

  defp tts_provider_module do
    Application.get_env(:stt_playground, :tts_provider, SttPlayground.TTS.PythonPort)
  end

  defp stt_provider_opts(SttPlayground.STT.PythonPort) do
    base = [
      worker_path: worker_path(),
      queue_max: Application.get_env(:stt_playground, :stt_queue_max, 128),
      drain_interval_ms: Application.get_env(:stt_playground, :stt_drain_interval_ms, 10),
      drain_batch_size: Application.get_env(:stt_playground, :stt_drain_batch_size, 32),
      overload_policy: Application.get_env(:stt_playground, :stt_overload_policy, :drop_newest)
    ]

    user = Application.get_env(:stt_playground, :stt_provider_opts, [])
    Keyword.merge(base, user)
  end

  defp stt_provider_opts(_other_provider) do
    Application.get_env(:stt_playground, :stt_provider_opts, [])
  end

  defp tts_provider_opts(SttPlayground.TTS.PythonPort) do
    base = [worker_path: tts_worker_path()]
    user = Application.get_env(:stt_playground, :tts_provider_opts, [])
    Keyword.merge(base, user)
  end

  defp tts_provider_opts(_other_provider) do
    Application.get_env(:stt_playground, :tts_provider_opts, [])
  end

  defp worker_path do
    System.get_env("STT_WORKER_PATH") || Path.expand("./stt_port_worker.py", File.cwd!())
  end

  defp tts_worker_path do
    System.get_env("TTS_WORKER_PATH") || Path.expand("./tts_port_worker.py", File.cwd!())
  end
end
