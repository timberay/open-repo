import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown", "current"]
  static values = {
    open: { type: Boolean, default: false }
  }

  connect() {
    this.closeOnClickOutside = this.closeOnClickOutside.bind(this)
  }

  toggle() {
    this.openValue = !this.openValue
  }

  open() {
    this.openValue = true
    document.addEventListener("click", this.closeOnClickOutside)
  }

  close() {
    this.openValue = false
    document.removeEventListener("click", this.closeOnClickOutside)
  }

  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  openValueChanged() {
    if (this.openValue) {
      this.dropdownTarget.classList.remove("hidden")
    } else {
      this.dropdownTarget.classList.add("hidden")
    }
  }

  selectRegistry(event) {
    const registryId = event.currentTarget.dataset.registryId
    
    if (!registryId) return

    this.close()

    fetch(`/registries/${registryId}/switch`, {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
      }
    }).then(response => {
      if (response.ok) {
        window.location.href = "/"
      }
    })
  }

  selectEnvRegistry(event) {
    this.close()

    fetch("/registries/switch_to_env", {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
      }
    }).then(response => {
      if (response.ok) {
        window.location.href = "/"
      }
    })
  }

  disconnect() {
    document.removeEventListener("click", this.closeOnClickOutside)
  }
}
