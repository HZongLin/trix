#= require trix/models/attachment
#= require trix/models/piece

Trix.Piece.registerType "attachment", class Trix.AttachmentPiece extends Trix.Piece
  @fromJSON: (pieceJSON) ->
    new this Trix.Attachment.fromJSON(pieceJSON.attachment), pieceJSON.attributes

  constructor: (@attachment) ->
    super
    @length = 1
    @ensureAttachmentExclusivelyHasAttribute("href")

  ensureAttachmentExclusivelyHasAttribute: (attribute) ->
    if @hasAttribute(attribute)
      unless @attachment.hasAttribute(attribute)
        @attachment.setAttributes(@attributes.slice(attribute))
      @attributes = @attributes.remove(attribute)

  getValue: ->
    @attachment

  isSerializable: ->
    not @attachment.isPending()

  getCaption: ->
    @attributes.get("caption") ? ""

  getAttributesForAttachment: ->
    @attributes.slice(["caption", "group"])

  canBeGrouped: ->
    @hasAttribute("group") and @attachment.isPreviewable()

  canBeGroupedWith: (piece) ->
    @getAttribute("group") is piece.getAttribute("group")

  isEqualTo: (piece) ->
    super and @attachment.id is piece?.attachment?.id

  toString: ->
    Trix.OBJECT_REPLACEMENT_CHARACTER

  toJSON: ->
    json = super
    json.attachment = @attachment
    json

  getCacheKey: ->
    [super, @attachment.getCacheKey()].join("/")

  toConsole: ->
    JSON.stringify(@toString())
