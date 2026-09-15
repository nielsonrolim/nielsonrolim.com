import { Controller } from "@hotwired/stimulus"

// Auto-dismisses a toast and lets a click close it early. The element is
// removed after the leaving transition, with a timeout as a fallback for
// reduced-motion users (where transitionend never fires).
export default class extends Controller {
  static values = { delay: { type: Number, default: 4000 } }

  connect() {
    this.timeout = setTimeout(() => this.dismiss(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timeout)
    clearTimeout(this.removeTimeout)
  }

  dismiss() {
    clearTimeout(this.timeout)
    this.element.classList.add("toast--leaving")
    this.removeTimeout = setTimeout(() => this.element.remove(), 400)
  }
}
