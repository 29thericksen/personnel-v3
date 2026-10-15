import { Controller } from '@hotwired/stimulus'

// Type-to-search picker for adding guests to an AAR. Each picked guest is a
// chip holding a hidden event[guest_ids][] input, so the form submits them
// with no extra wiring.
export default class extends Controller {
  static targets = ['input', 'menu', 'chips']
  static values = { url: String }

  connect() {
    this.results = []
    this.active = -1
    this._onOutsideClick = (event) => {
      if (!this.element.contains(event.target)) this._close()
    }
    document.addEventListener('click', this._onOutsideClick)
  }

  disconnect() {
    document.removeEventListener('click', this._onOutsideClick)
    clearTimeout(this.timer)
    this.request?.abort()
  }

  search() {
    clearTimeout(this.timer)
    const query = this.inputTarget.value.trim()
    if (query.length < 2) {
      this._close()
      return
    }
    this.timer = setTimeout(() => this._fetch(query), 250)
  }

  navigate(event) {
    switch (event.key) {
      case 'ArrowDown':
        event.preventDefault()
        this._highlight(Math.min(this.active + 1, this.results.length - 1))
        break
      case 'ArrowUp':
        event.preventDefault()
        this._highlight(Math.max(this.active - 1, 0))
        break
      case 'Enter':
        // never submit the AAR form from the search box
        event.preventDefault()
        if (this.results[this.active]) this._add(this.results[this.active])
        break
      case 'Escape':
        this._close()
        break
      case 'Backspace':
        if (this.inputTarget.value === '') this.chipsTarget.lastElementChild?.remove()
        break
    }
  }

  pick(event) {
    const result = this.results[Number(event.currentTarget.dataset.index)]
    if (result) this._add(result)
  }

  remove(event) {
    event.currentTarget.closest('[data-guest-id]').remove()
    this.inputTarget.focus()
  }

  async _fetch(query) {
    this.request?.abort()
    this.request = new AbortController()

    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set('q', query)

    try {
      const response = await fetch(url, {
        headers: { Accept: 'application/json' },
        credentials: 'same-origin',
        signal: this.request.signal
      })
      if (!response.ok) throw new Error(`Guest search failed: ${response.status}`)

      const chosen = this._chosenIds()
      this.results = (await response.json()).filter((result) => !chosen.includes(String(result.id)))
      this.active = this.results.length ? 0 : -1
      this._renderMenu()
    } catch (error) {
      if (error.name !== 'AbortError') this._renderMessage('Search failed. Try again.')
    }
  }

  _add(result) {
    const chip = document.createElement('span')
    chip.className = 'badge badge-secondary guest-picker-chip'
    chip.dataset.guestId = result.id

    const name = document.createElement('span')
    name.textContent = result.name
    const detail = document.createElement('small')
    detail.textContent = ` (${result.detail})`

    const input = document.createElement('input')
    input.type = 'hidden'
    input.name = 'event[guest_ids][]'
    input.value = result.id

    const button = document.createElement('button')
    button.type = 'button'
    button.className = 'close'
    button.setAttribute('aria-label', `Remove ${result.name}`)
    button.dataset.action = 'guest-picker#remove'
    button.textContent = '×'

    chip.append(name, detail, input, button)
    this.chipsTarget.append(chip)

    this.inputTarget.value = ''
    this._close()
    this.inputTarget.focus()
  }

  _renderMenu() {
    if (this.results.length === 0) {
      this._renderMessage('No matching members. Members expected at this event are not listed.')
      return
    }

    this.menuTarget.replaceChildren(...this.results.map((result, index) => {
      const item = document.createElement('button')
      item.type = 'button'
      item.className = 'dropdown-item'
      item.dataset.index = index
      item.dataset.action = 'guest-picker#pick'
      item.setAttribute('role', 'option')

      const detail = document.createElement('small')
      detail.className = 'text-muted'
      detail.textContent = ` ${result.detail}`
      item.append(document.createTextNode(result.name), detail)
      return item
    }))
    this._highlight(this.active)
    this._open()
  }

  _renderMessage(message) {
    const item = document.createElement('span')
    item.className = 'dropdown-item-text text-muted'
    item.textContent = message
    this.menuTarget.replaceChildren(item)
    this.results = []
    this.active = -1
    this._open()
  }

  _highlight(index) {
    this.active = index
    Array.from(this.menuTarget.children).forEach((item, i) => {
      item.classList.toggle('active', i === index)
      item.setAttribute('aria-selected', i === index)
    })
  }

  _chosenIds() {
    return Array.from(this.chipsTarget.querySelectorAll('[data-guest-id]'))
      .map((chip) => chip.dataset.guestId)
  }

  _open() {
    this.menuTarget.classList.add('show')
    this.inputTarget.setAttribute('aria-expanded', 'true')
  }

  _close() {
    this.menuTarget.classList.remove('show')
    this.inputTarget.setAttribute('aria-expanded', 'false')
  }
}
