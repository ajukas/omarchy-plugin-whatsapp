#!/bin/bash
# Show/hide WhatsApp Web as a popup in the special:whatsapp workspace, pinned
# to the top-right corner of the focused monitor.
#
#   whatsapp-popup.sh toggle [url]   show, hide, or launch it
#   whatsapp-popup.sh hide           hide it once another window has focus, pulling it
#                                    back if it was dragged out
#   whatsapp-popup.sh dismiss        hide it unconditionally (click on empty desktop)
#   whatsapp-popup.sh evict          move other windows that opened inside the popup's
#                                    workspace onto the monitor's regular one

WIDTH=1300
HEIGHT=850
MARGIN=12 # gaps_out + border, so it lines up with tiled windows
SPECIAL=whatsapp
URL=${2:-https://web.whatsapp.com/}

dispatch() { hyprctl dispatch "$1" >/dev/null; }

# Every bar (one per monitor) reacts to focus changes, so serialize the runs.
# The timeout keeps a stale lock from blocking every later click.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/whatsapp-popup.lock"
flock -w 5 9 || exit 1

window=$(hyprctl clients -j | jq -c 'first(.[] | select(.class | test("-web\\.whatsapp\\.com__"))) // empty')
address=$(jq -r '.address // empty' <<<"$window")
workspace=$(jq -r '.workspace.name // empty' <<<"$window")
monitor=$(hyprctl monitors -j | jq -c 'first(.[] | select(.focused))')
shown=$(jq -r --arg ws "special:$SPECIAL" '.specialWorkspace.name == $ws' <<<"$monitor")

# Dragging a window out of a special workspace drops it onto a regular one.
pull_back() {
  dispatch "hl.dsp.window.move({ workspace = \"special:$SPECIAL\", follow = false, window = \"address:$address\" })"
}

hide() {
  if [[ $workspace != "special:$SPECIAL" ]]; then
    pull_back
  elif [[ $shown == true ]]; then
    dispatch "hl.dsp.workspace.toggle_special(\"$SPECIAL\")"
  fi
}

place() {
  local x y
  read -r x y < <(jq -r --argjson w "$WIDTH" --argjson m "$MARGIN" '
    (.width / .scale) as $mw
    | "\((.x + $mw - $w - .reserved[2] - $m) | floor) \((.y + .reserved[1] + $m) | floor)"' <<<"$monitor")
  [[ $(jq -r '.floating' <<<"$window") == true ]] || dispatch "hl.dsp.window.float({ action = \"enable\", window = \"address:$address\" })"
  dispatch "hl.dsp.window.resize({ x = $WIDTH, y = $HEIGHT, relative = false, window = \"address:$address\" })"
  dispatch "hl.dsp.window.move({ x = $x, y = $y, relative = false, window = \"address:$address\" })"
}

show() {
  dispatch "hl.dsp.workspace.toggle_special(\"$SPECIAL\")"
  place
  # Focusing a window warps the cursor into it; keep the cursor where it is.
  local no_warps
  no_warps=$(hyprctl getoption cursor:no_warps -j | jq -r '.bool // .int // false')
  [[ $no_warps == true || $no_warps == 1 ]] && no_warps=true || no_warps=false
  hyprctl eval "hl.config({ cursor = { no_warps = true } })" >/dev/null
  dispatch "hl.dsp.focus({ window = \"address:$address\" })"
  hyprctl eval "hl.config({ cursor = { no_warps = $no_warps } })" >/dev/null
  # The popup appears under a cursor that has not moved, so the pointer still
  # targets the surface below it and touchpad scrolling misses WhatsApp. Moving
  # the cursor onto itself makes Hyprland pick the surface under it again.
  local cx cy
  read -r cx cy < <(hyprctl cursorpos | tr -d ',')
  dispatch "hl.dsp.cursor.move({ x = $cx, y = $cy })"
}

case $1 in
  toggle)
    if [[ -z $address ]]; then
      # Close the lock fd first: if this starts the browser, it would otherwise
      # inherit the lock and hold it for as long as the browser runs.
      exec omarchy-launch-webapp "$URL" 9>&-
    elif [[ $workspace != "special:$SPECIAL" || $shown == true ]]; then
      hide
    else
      show
    fi
    ;;
  hide)
    [[ -n $address && $(hyprctl activewindow -j | jq -r '.address') != "$address" ]] && hide
    ;;
  dismiss)
    [[ -n $address ]] && hide
    ;;
  evict)
    # While the popup is shown and focused, Hyprland opens new windows on
    # special:$SPECIAL too; send them to the regular workspace underneath.
    strays=$(hyprctl clients -j | jq -r --arg ws "special:$SPECIAL" \
      '.[] | select(.workspace.name == $ws and ((.class | test("-web\\.whatsapp\\.com__")) | not)) | "\(.address) \(.monitor)"')
    [[ -z $strays ]] && exit 0
    monitors=$(hyprctl monitors -j)
    while read -r stray mon; do
      target=$(jq -r --argjson id "$mon" 'first(.[] | select(.id == $id) | .activeWorkspace.id) // empty' <<<"$monitors")
      [[ -z $target ]] && target=$(jq -r '.activeWorkspace.id' <<<"$monitor")
      dispatch "hl.dsp.window.move({ workspace = \"$target\", follow = false, window = \"address:$stray\" })"
    done <<<"$strays"
    [[ $shown == true ]] && dispatch "hl.dsp.workspace.toggle_special(\"$SPECIAL\")"
    dispatch "hl.dsp.focus({ window = \"address:$stray\" })"
    ;;
esac
