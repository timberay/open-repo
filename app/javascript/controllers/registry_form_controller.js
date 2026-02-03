import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["url", "username", "password", "testButton", "testResult", "testIcon", "testMessage"]

  testConnection(event) {
    event.preventDefault()

    const url = this.urlTarget.value
    const username = this.usernameTarget.value
    const password = this.passwordTarget.value

    if (!url) {
      this.showError("Please enter a registry URL")
      return
    }

    this.showTesting()

    const formData = new FormData()
    formData.append("registry[url]", url)
    if (username) formData.append("registry[username]", username)
    if (password) formData.append("registry[password]", password)

    const testUrl = this.element.dataset.testUrl || "/registries/test_connection"

    fetch(testUrl, {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content,
        "Accept": "application/json"
      },
      body: formData
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        this.showSuccess(data.message)
      } else {
        this.showError(data.message)
      }
    })
    .catch(error => {
      this.showError("Connection test failed: " + error.message)
    })
  }

  showTesting() {
    this.testResultTarget.classList.remove("hidden")
    this.testResultTarget.classList.remove("bg-green-50", "bg-red-50", "dark:bg-green-900/20", "dark:bg-red-900/20")
    this.testResultTarget.classList.add("bg-blue-50", "dark:bg-blue-900/20")
    
    this.testIconTarget.classList.remove("text-green-600", "text-red-600")
    this.testIconTarget.classList.add("text-blue-600", "animate-spin")
    this.testIconTarget.innerHTML = `
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
      </svg>
    `
    this.testMessageTarget.textContent = "Testing connection..."
    this.testButtonTarget.disabled = true
  }

  showSuccess(message) {
    this.testResultTarget.classList.remove("hidden", "bg-blue-50", "bg-red-50", "dark:bg-blue-900/20", "dark:bg-red-900/20")
    this.testResultTarget.classList.add("bg-green-50", "dark:bg-green-900/20")
    
    this.testIconTarget.classList.remove("text-blue-600", "text-red-600", "animate-spin")
    this.testIconTarget.classList.add("text-green-600")
    this.testIconTarget.innerHTML = `
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
      </svg>
    `
    this.testMessageTarget.textContent = message
    this.testButtonTarget.disabled = false
  }

  showError(message) {
    this.testResultTarget.classList.remove("hidden", "bg-blue-50", "bg-green-50", "dark:bg-blue-900/20", "dark:bg-green-900/20")
    this.testResultTarget.classList.add("bg-red-50", "dark:bg-red-900/20")
    
    this.testIconTarget.classList.remove("text-blue-600", "text-green-600", "animate-spin")
    this.testIconTarget.classList.add("text-red-600")
    this.testIconTarget.innerHTML = `
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
      </svg>
    `
    this.testMessageTarget.textContent = message
    this.testButtonTarget.disabled = false
  }
}
