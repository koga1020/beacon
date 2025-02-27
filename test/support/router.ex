defmodule Beacon.BeaconTest.Router do
  use Beacon.BeaconTest, :router
  import Beacon.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/" do
    pipe_through :browser
    beacon_admin "/admin"
    beacon_site "/", site: :my_site
  end
end
