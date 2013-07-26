The additional files in this directory aren't part of the Brightnesser code, but
are useful or necessary to run it.

* brightnesserd.service
  systemd unit file for running the Brightnesser daemon in the background.
  Belongs into /usr/lib/systemd/system or /etc/systemd/system.

* com.ondrahosek.Brightnesser.conf
  Brightnesser daemon D-Bus configuration.
  Belongs into /etc/dbus-1/system.d.

* com.ondrahosek.Brightnesser.policy
  Brightnesser daemon Polkit policy.
  Belongs into /usr/share/polkit-1/actions.

* com.ondrahosek.Brightnesser.service
  Brightnesser daemon D-Bus service info.
  Optional.
  Belongs into /usr/share/dbus-1/system-services.
