#= require trix/observers/mutation_observer
#= require trix/operations/file_verification_operation

{handleEvent, findClosestElementFromNode, findElementForContainerAtOffset, defer} = Trix

class Trix.InputController extends Trix.BasicObject
  pastedFileCount = 0

  @keyNames:
    "8":  "backspace"
    "9":  "tab"
    "13": "return"
    "37": "left"
    "39": "right"
    "68": "d"
    "72": "h"
    "79": "o"

  constructor: (@element) ->
    @mutationObserver = new Trix.MutationObserver @element
    @mutationObserver.delegate = this

    for eventName of @events
      handleEvent eventName, onElement: @element, withCallback: @handlerFor(eventName), inPhase: "capturing"

  handlerFor: (eventName) ->
    (event) =>
      try
        @events[eventName].call(this, event)
      catch error
        @delegate?.inputControllerDidThrowError?(error, {eventName})
        throw error

  # Render cycle

  editorWillRender: ->
    @mutationObserver.stop()

  editorDidRender: ->
    @mutationObserver.start()

  requestRender: ->
    @delegate?.inputControllerDidRequestRender?()
    @resetInput()

  resetInput: ->
    delete @input

  # Mutation observer delegate

  elementDidMutate: ({textAdded, textDeleted}) ->
    try
      console.group "Mutation: #{JSON.stringify({@input, textAdded, textDeleted})}"
      unhandledAddition = textAdded? and textAdded isnt @input
      unhandledDeletion = textDeleted? and @input isnt "delete"
      if unhandledAddition or unhandledDeletion
        @responder?.replaceHTML(@element.innerHTML)
      @requestRender()
      console.groupEnd()
    catch error
      @delegate?.inputControllerDidThrowError?(error, {mutations})
      throw error

  # File verification

  attachFiles: (files) ->
    operations = (new Trix.FileVerificationOperation(file) for file in files)
    Promise.all(operations).then (files) =>
      @delegate?.inputControllerWillAttachFiles()
      @responder?.insertFile(file) for file in files
      @requestRender()

  # Input handlers

  events:
    keydown: (event) ->
      @resetInput()
      if keyName = @constructor.keyNames[event.keyCode]
        context = @keys
        for modifier in ["ctrl", "alt", "shift"] when event["#{modifier}Key"]
          modifier = "control" if modifier is "ctrl"
          context = @keys[modifier]
          break if context[keyName]

        if context[keyName]?
          context[keyName].call(this, event)

      if keyEventIsKeyboardCommand(event)
        if character = String.fromCharCode(event.keyCode).toLowerCase()
          keys = (modifier for modifier in ["alt", "shift"] when event["#{modifier}Key"])
          keys.push(character)
          if @delegate?.inputControllerDidReceiveKeyboardCommand(keys)
            event.preventDefault()

    keypress: (event) ->
      return if @input?
      return if (event.metaKey or event.ctrlKey) and not event.altKey
      return if keyEventIsWebInspectorShortcut(event)
      return if keyEventIsPasteAndMatchStyleShortcut(event)

      if event.which is null
        character = String.fromCharCode event.keyCode
      else if event.which isnt 0 and event.charCode isnt 0
        character = String.fromCharCode event.charCode

      if character?
        @delegate?.inputControllerWillPerformTyping()
        @responder?.insertString(character)
        @input = character

    dragenter: (event) ->
      event.preventDefault()

    dragstart: (event) ->
      target = event.target
      @draggedRange = @responder?.getLocationRange()
      @delegate?.inputControllerDidStartDrag?()

    dragover: (event) ->
      if @draggedRange or "Files" in event.dataTransfer?.types
        event.preventDefault()
        draggingPoint = [event.clientX, event.clientY]
        if draggingPoint.toString() isnt @draggingPoint?.toString()
          @draggingPoint = draggingPoint
          @delegate?.inputControllerDidReceiveDragOverPoint?(@draggingPoint)

    dragend: (event) ->
      @delegate?.inputControllerDidCancelDrag?()
      delete @draggedRange
      delete @draggingPoint

    drop: (event) ->
      event.preventDefault()
      point = [event.clientX, event.clientY]
      @responder?.setLocationRangeFromPoint(point)

      if @draggedRange
        @delegate?.inputControllerWillMoveText()
        @responder?.moveTextFromLocationRange(@draggedRange)
        delete @draggedRange

      else if files = event.dataTransfer.files
        @attachFiles(event.dataTransfer.files)

      delete @draggedRange
      delete @draggingPoint

    cut: (event) ->
      @delegate?.inputControllerWillCutText()
      @deleteInDirection("backward")

    paste: (event) ->
      paste = event.clipboardData ? event.testClipboardData
      return unless paste?
      return for type in paste.types when type.match(/^com\.apple/)
      event.preventDefault()

      if html = paste.getData("text/html")
        @delegate?.inputControllerWillPasteText({paste, html})
        @responder?.insertHTML(html)
      else if string = paste.getData("text/plain")
        @delegate?.inputControllerWillPasteText({paste, string})
        @responder?.insertString(string)

      if "Files" in paste.types
        if file = paste.items?[0]?.getAsFile?()
          if not file.name and extension = extensionForFile(file)
            file.name = "pasted-file-#{++pastedFileCount}.#{extension}"
          @delegate?.inputControllerWillAttachFiles()
          if @responder?.insertFile(file)
            file.trixInserted = true

    compositionstart: (event) ->
      @mutationObserver.stop()

    compositionend: (event) ->
      if (composedString = event.data)?
        @delegate?.inputControllerWillPerformTyping()
        @responder?.insertString(composedString)
      @mutationObserver.start()

  keys:
    backspace: (event) ->
      @delegate?.inputControllerWillPerformTyping()
      @deleteInDirection("backward")

    return: (event) ->
      @delegate?.inputControllerWillPerformTyping()
      @responder?.insertLineBreak()
      @input = "return"

    tab: (event) ->
      if @responder?.canChangeBlockAttributeLevel()
        @responder?.increaseBlockAttributeLevel()
        event.preventDefault()

    left: (event) ->
      if @selectionIsInCursorTarget()
        event.preventDefault()
        @responder?.moveCursorInDirection("backward")

    right: (event) ->
      if @selectionIsInCursorTarget()
        event.preventDefault()
        @responder?.moveCursorInDirection("forward")

    control:
      d: (event) ->
        @delegate?.inputControllerWillPerformTyping()
        @deleteInDirection("forward")

      h: (event) ->
        @delegate?.inputControllerWillPerformTyping()
        @deleteInDirection("backward")

      o: (event) ->
        event.preventDefault()
        @delegate?.inputControllerWillPerformTyping()
        @responder?.insertString("\n", updatePosition: false)
        @requestRender()

    alt:
      backspace: (event) ->
        @delegate?.inputControllerWillPerformTyping()
        @input = "alt+backspace"

    shift:
      return: (event) ->
        @delegate?.inputControllerWillPerformTyping()
        @responder?.insertString("\n")
        @input = "shift+return"

      left: (event) ->
        if @selectionIsInCursorTarget()
          event.preventDefault()
          @responder?.expandSelectionInDirection("backward")

      right: (event) ->
        if @selectionIsInCursorTarget()
          event.preventDefault()
          @responder?.expandSelectionInDirection("forward")

  deleteInDirection: (direction) ->
    @responder?.deleteInDirection(direction)
    @input = "delete"

  selectionIsInCursorTarget: ->
    @responder?.selectionIsInCursorTarget()

  extensionForFile = (file) ->
    file.type?.match(/\/(\w+)$/)?[1]

keyEventIsWebInspectorShortcut = (event) ->
  event.metaKey and event.altKey and not event.shiftKey and event.keyCode is 94

keyEventIsPasteAndMatchStyleShortcut = (event) ->
  event.metaKey and event.altKey and event.shiftKey and event.keyCode is 9674

keyEventIsKeyboardCommand = (event) ->
  if /Mac|^iP/.test(navigator.platform) then event.metaKey else event.ctrlKey
