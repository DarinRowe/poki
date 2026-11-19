// UIKit exposes points in the current interface orientation. The digitizer
// receives normalized coordinates in the display's native portrait axes.
export function portraitTouch(x, y, orientation) {
  switch (orientation) {
    case 'landscape_left': return [y, 1 - x];
    case 'landscape_right': return [1 - y, x];
    default: return [x, y];
  }
}
