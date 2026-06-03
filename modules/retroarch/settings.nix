{ romsDirectory }:

{
  menu_driver = "rgui";
  rgui_aspect_ratio_lock = "2";
  audio_driver = "pipewire";
  audio_latency = "64";
  input_driver = "udev";
  input_joypad_driver = "udev";
  savestate_auto_load = "true";
  savestate_auto_save = "true";
  rgui_browser_directory = romsDirectory;

  # Hide menu items
  content_show_contentless_cores = "0";
  content_show_explore = "false";
  content_show_favorites = "false";
  content_show_history = "true";
  content_show_images = "false";
  content_show_music = "false";
  content_show_video = "false";
  content_show_netplay = "false";
  menu_show_quit_retroarch = "true";
  menu_show_shutdown = "true";
  menu_show_reboot = "true";

  # Video — RA's own set_fullscreen call deadlocks the render thread on
  # cage; instead we use a custom viewport that fills the compositor's
  # logical surface. RA's `aspect_ratio_index = 23` (Custom) + the
  # custom_viewport_* values below tell the glcore driver to render the
  # core's output at 0,0 sized to 640x480 — which matches cage's
  # post-kanshi-transform surface size. Without this, RA falls back to
  # its scale-based windowed size (240×160 × scale=2 ≈ 480×320) and
  # leaves the rest of the surface unused, manifesting as a small
  # picture in a corner.
  video_fullscreen = "false";
  video_allow_rotate = "true";
  video_force_aspect = "true";
  aspect_ratio_index = "23";
  custom_viewport_width = "640";
  custom_viewport_height = "480";
  custom_viewport_x = "0";
  custom_viewport_y = "0";
  video_scale = "2";
  video_vsync = "false";
  video_smooth = "false";
  video_shader_enable = "false";
  video_threaded = "true";

  # Theme
  rgui_menu_color_theme = "20";

  # Hide date/time (no RTC, clock is always wrong)
  menu_timedate_enable = "false";

  # Disable online features (no network)
  menu_show_online_updater = "false";
  menu_show_core_updater = "false";

  # Input
  input_player1_analog_dpad_mode = "1";
  input_analog_sensitivity = "1.0";

  # Hotkeys — M button (BTN_MODE = button 10 on H700, sometimes labeled
  # Home on similar pads) opens the RetroArch menu. Disable the legacy
  # Start+Select combo since the dedicated button is unambiguous.
  input_menu_toggle_btn = "10";
  input_menu_toggle_gamepad_combo = "0";
  input_exit_emulator_btn = "nul";
  menu_swap_ok_cancel_buttons = "false";

  # Volume keys
  input_volume_up = "volumeup";
  input_volume_down = "volumedown";

  # Paths — on roms card so they survive reflash
  system_directory = "${romsDirectory}/bios";
  savefile_directory = "${romsDirectory}/saves";
  savestate_directory = "${romsDirectory}/states";

  # Pin to stable symlink so retroarch.cfg can't cache a stale nix store path
  libretro_directory = "/run/retroarch/cores";

  # Log to file so we can see RA stderr after ES `system()`s a launch
  # (cage's stdout/stderr capture isn't reliable across the ES → fork
  # boundary). /tmp is tmpfs — log resets on reboot, which is fine.
  log_to_file = "true";
  log_to_file_timestamp = "false";
  log_dir = "/tmp";
  log_verbosity = "1";
  frontend_log_level = "0";
}
