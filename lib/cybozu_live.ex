defmodule CybozuLive do
  @step_1 "https://api.cybozulive.com/oauth/initiate"
  @step_2 "https://api.cybozulive.com/oauth/authorize"
  @step_3 "https://api.cybozulive.com/oauth/token"

  @notification "https://api.cybozulive.com/api/notification/V2"

  require Logger

  def start() do
    {:ok, {token, token_secret}} = get_token

    creds = OAuther.credentials(consumer_key: Application.get_env(:cybozu_live, :consumer_key),
      consumer_secret: Application.get_env(:cybozu_live, :consumer_secret), token: token, token_secret: token_secret)

    params = OAuther.sign("get", @notification, [], creds)
    {header, _req_params} = OAuther.header(params)
    HTTPoison.get(@notification, [header])

  end

  def auth() do
    Logger.info "start OAuth sequence"

    creds = OAuther.credentials(consumer_key: Application.get_env(:cybozu_live, :consumer_key),
      consumer_secret: Application.get_env(:cybozu_live, :consumer_secret))

    params = OAuther.sign("get", @step_1, [], creds)

    {header, _req_params} = OAuther.header(params)

    {:ok, res}= HTTPoison.get(@step_1, [header])

    %{"oauth_token" => oauth_token, "oauth_token_secret" => oauth_token_secret} =
      URI.decode_query(res.body, %{})

    System.cmd("xdg-open", [@step_2 <> "?oauth_token=#{oauth_token}"])

    {:ok, verifier} = get_verifier

    creds = %{creds| token: oauth_token, token_secret: oauth_token_secret}

    params = OAuther.sign("get", @step_3, [{"oauth_verifier", verifier}], creds)

    {header, _req_params} = OAuther.header(params)

    {:ok, res} = HTTPoison.get(@step_3, [header])
    %{"oauth_token" => oauth_token, "oauth_token_secret" => oauth_token_secret} =
      URI.decode_query(res.body, %{})

    {:ok, {oauth_token, oauth_token_secret}}
  end

  defp get_verifier do
    case IO.gets("verifier code: ") do
      {:error, reason} ->
        Logger.warn "get verifier failed: #{reason}"
        :error
      :eof ->
        Logger.warn "get verifier failed: eof"
        :error
      data ->
        {:ok, String.trim(data)}
    end

  end

  defp get_token do
    {:ok, table} = :dets.open_file(:token, [type: :set])

    consumer_key = Application.get_env(:cybozu_live, :consumer_key)

    case :dets.lookup(table, consumer_key) do
      [{^consumer_key, {token, token_secret}} | _ ] ->
        {:ok, {token, token_secret}}
      _ ->
        case auth() do
          {:ok, token} ->
            :dets.insert(table, {consumer_key, token})
            {:ok, token}
        end
    end

  end

end
