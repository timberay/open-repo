import { Controller } from "@hotwired/stimulus"

// Shows the custom regex input only when the policy select is set to
// "custom_regex". Data-driven, no DOM assumptions beyond the two targets.
export default class extends Controller {
  static targets = ["policy", "regexWrapper"]

  connect() {
    this.toggle()
  }

  toggle() {
    const shouldShow = this.policyTarget.value === "custom_regex"
    this.regexWrapperTarget.hidden = !shouldShow
  }
}
