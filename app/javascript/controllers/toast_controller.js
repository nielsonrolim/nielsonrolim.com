import { Controller } from "@hotwired/stimulus"

// Auto-dismisses a toast and lets a click close it early. The element is
// removed after the leaving transition, with a timeout as a fallback for
// reduced-motion users (where transitionend never fires). While the visitor
// hovers or focuses the toast (e.g. the close button), the countdown pauses.
export default class extends Controller {
  static values = { delay: { type: Number, default: 4000 } }

  connect() {
    this.schedule()
  }

  disconnect() {
    clearTimeout(this.timeout)
    clearTimeout(this.removeTimeout)
  }

  pause() {
    clearTimeout(this.timeout)
  }

  resume() {
    this.schedule()
  }

  dismiss() {
    clearTimeout(this.timeout)
    this.element.classList.add("toast--leaving")
    this.removeTimeout = setTimeout(() => this.element.remove(), 400)
  }

  schedule() {
    this.timeout = setTimeout(() => this.dismiss(), this.delayValue)
  }
}
