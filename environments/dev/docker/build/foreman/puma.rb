# Docker-specific Puma config for Foreman.
# The production config uses bind_to_activated_sockets 'only' which requires
# systemd socket activation — unavailable in Docker. This config binds directly.

threads 0, 16
workers 2
preload_app!

bind "tcp://0.0.0.0:3000"


on_worker_boot do
  dynflow = ::Rails.application.dynflow
  dynflow.initialize! unless dynflow.config.lazy_initialization
end

before_fork do
  Foreman::Gettext::Support.human_available_locales
end
