class EditableController extends Controller

  _getRange: ->
    sel = @app.window.getSelection()
    sel.getRangeAt(0) if sel.rangeCount > 0

  # AKA, the "move the cursor [before|after] the given node" function
  _setRange: (position, node, range=@_getRange()) ->
    return unless range
    node = $(node)[0]
    if position == 'after'
      range.setEndAfter node
      range.setStartAfter node
    else
      range.setEndBefore node
      range.setStartBefore node
    range.collapse false
    @_clearRange range

  _clearRange: (range=@_getRange()) ->
    sel = @app.window.getSelection()
    #ctrl+a remove defaults using the flag
    if !@ctrl_a_pressed?
      sel.removeAllRanges()
      sel.addRange range

  _movingEvent: (e) ->
    e.type == 'click' or e.which in [KEY_CODE.RIGHT, KEY_CODE.LEFT, KEY_CODE.UP, KEY_CODE.DOWN]

  _unwrap: (node) ->
    node = $(node).unwrap().get 0
    if (next = node.nextSibling) and next.nodeValue
      node.nodeValue += next.nodeValue
      $(next).remove()
    node

  catchQuery: (e) ->
    return unless range = @_getRange()
    return unless range.collapsed

    console.log "================================================================="

    console.log "Key code: ", e.which

    console.log "1"

    # No <font>s allowed
    @$inputor.find('font').each () ->
      $(this).before($(this).text()).remove()

    if e.which == KEY_CODE.ENTER
      ($query = $(range.startContainer).closest '.atwho-query')
        .contents().unwrap()
      $query.remove() if $query.is ':empty'
      ($query = $ ".atwho-query", @app.document)
        .text $query.text()
        .contents().last().unwrap()
      @_clearRange()
      return

    console.log "2"

    # absorb range
    # The range at the end of an element is not inside in firefox but not others
    # browsers including IE. To normolize them, we have to move the range inside
    # the element while deleting content or moving caret right after
    # .atwho-inserted
    if /firefox/i.test(navigator.userAgent)
      console.log "f1"
      if $(range.startContainer).is @$inputor
        console.log "f2"
        # @_clearRange()
        # return
      if e.which == KEY_CODE.BACKSPACE and range.startContainer.nodeType == document.ELEMENT_NODE \
          and (offset = range.startOffset - 1) >= 0
        console.log "f3"
        _range = range.cloneRange()
        _range.setStart range.startContainer, offset
        if $(_range.cloneContents()).contents().last().is '.atwho-inserted'
          inserted = $(range.startContainer).contents().get(offset)
          @_setRange 'after', $(inserted).contents().last()
      else if e.which == KEY_CODE.LEFT and range.startContainer.nodeType == document.TEXT_NODE
        console.log "f4"
        $inserted = $ range.startContainer.previousSibling
        if $inserted.is('.atwho-inserted') and range.startOffset == 0
          console.log "f5"
          @_setRange 'after', $inserted.contents().last()


    # modifying inserted element
    # Correcting atwho-inserted and atwho-query classes based on current cursor position
    $(range.startContainer)
      .closest '.atwho-inserted'
      .addClass 'atwho-query'
      .siblings().removeClass 'atwho-query'


    console.log "3"

    if ($query = $ ".atwho-query", @app.document).length > 0 \
        and $query.is(':empty') and $query.text().length == 0
      $query.remove()
      return

    console.log "4"

    # EVERYTHING BELOW HERE IS EXECUTED ONLY IF THERE IS AN .atwho-query ELEMENT

    if not @_movingEvent e
      console.log "5a"
      $query.removeClass 'atwho-inserted'
    else
      console.log "5b"
      return if $query.length > 0

    # If the value has been changed at all
    if $query.length > 0 and query_content = $query.text()
      console.log "6"
      chosen = $query.attr('data-atwho-chosen-value')
      if e.which == KEY_CODE.BACKSPACE
        console.log "6a"
        $query.remove()
        return
      else if chosen and query_content != chosen
        console.log "6b"
        # $query.empty().html(query_content).attr('data-atwho-chosen-value', null)
        $query.before(query_content).remove()
        return

      # This ensures that the cursor stays where it's supposed to be when the user is typing in their query
      # ONLY ON NOT FIREFOX THOUGH CUZ OF COURSE
      if not /firefox/i.test navigator.userAgent
        @_setRange 'after', $query.get(0), range

    console.log "7"

    # matching
    # We now build a _range that contains the query text
    # Note: @at = whatever symbol this controller is registered for ('@', '#', etc); the `flag`
    _range = range.cloneRange()
    _range.setStart range.startContainer, 0
    matched = @callbacks("matcher").call(this, @at, _range.toString(), @getOpt('startWithSpace'), @getOpt("acceptSpaceBar"))
    isString = typeof matched is 'string'

    console.log "8"

    # wrapping query with .atwho-query
    if $query.length == 0 and isString \
        and (index = range.startOffset - @at.length - matched.length) >= 0
      console.log "8-"
      range.setStart range.startContainer, index
      $query = $ '<span/>', @app.document
        .attr @getOpt "editableAtwhoQueryAttrs"
        .addClass 'atwho-query'
      range.surroundContents $query.get 0
      lastNode = $query.contents().last().get(0)
      if /firefox/i.test navigator.userAgent
        console.log "8f"
        range.setStart lastNode, lastNode.length
        range.setEnd lastNode, lastNode.length
        @_clearRange range
      else
        console.log "8o"
        @_setRange 'after', lastNode, range

    console.log "9"
    return if isString and matched.length < @getOpt('minLen', 0)
    console.log "10", @getOpt('maxLen', 20)

    # handle the matched result
    if isString and matched != null and matched.length <= @getOpt('maxLen', 20)
      console.log "10a", isString, matched, ";", matched.length
      query = text: matched, el: $query
      @trigger "matched", [@at, query.text]
      @query = query
    else
      console.log "10b", isString, matched, matched.length
      @view.hide()
      @query = el: $query
      if $query.text().indexOf(this.at) >= 0
        console.log "10b-1"
        if @_movingEvent(e) and $query.hasClass 'atwho-inserted'
          console.log "10b-1a"
          $query.removeClass('atwho-query')
        else if false != @callbacks('afterMatchFailed').call this, @at, $query
          console.log "10b-1b"
          @_setRange "after", @_unwrap $query.text($query.text()).contents().first()
      null

  # Get offset of current at char(`flag`)
  #
  # @return [Hash] the offset which look likes this: {top: y, left: x, bottom: bottom}
  rect: ->
    rect = @query.el.offset()
    if @app.iframe and not @app.iframeAsRoot
      iframeOffset = ($iframe = $ @app.iframe).offset()
      rect.left += iframeOffset.left - @$inputor.scrollLeft()
      rect.top += iframeOffset.top - @$inputor.scrollTop()
    rect.bottom = rect.top + @query.el.height()
    rect

  # Insert value of `data-value` attribute of chosen item into inputor
  #
  # @param content [String] string to insert
  insert: (content, $li) ->
    @$inputor.focus() unless @$inputor.is ':focus'
    suffix = if (suffix = @getOpt 'suffix') == "" then suffix else suffix or "\u00A0"
    data = $li.data('item-data')
    @query.el
      .removeClass 'atwho-query'
      .addClass 'atwho-inserted'
      .html content
      .attr 'data-atwho-at-query', "" + data['atwho-at'] + @query.text
      .attr 'data-atwho-chosen-value', "" + data['atwho-at'] + content
    if range = @_getRange()
      range.setEndAfter @query.el[0]
      range.collapse false
      range.insertNode suffixNode = @app.document.createTextNode "\u200D" + suffix
      @_setRange 'after', suffixNode, range
    @$inputor.focus() unless @$inputor.is ':focus'
    @$inputor.change()
