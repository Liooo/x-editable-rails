unless EditableForm
  build_nested_param = (attr_to_update, updated_value, nested)->
    ret = {}
    last = ret
    if(Array.isArray(nested))
      for obj in nested
        attr = Object.keys(obj)[0]
        key = attr + "_attributes"
        id = obj[attr]
        last[key] = {id: id}
        last = last[key]
    else if (typeof nested == "object" && nested != null)
      attr = Object.keys(nested)[0]
      key = attr + "_attributes"
      id = nested[attr]
      last[key] = {id: id}
      last = last[key]

    last[attr_to_update] = updated_value
    ret

  EditableForm = $.fn.editableform.Constructor
  EditableForm.prototype.saveWithUrlHook = (value) ->
    originalUrl   = @options.url
    model         = @options.model
    nestedObj     = @options.nested
    nestedId      = @options.nid
    nestedLocale  = @options.locale

    @options.url = (params) =>
      if typeof originalUrl == 'function'
        originalUrl.call(@options.scope, params)
      else if originalUrl? && @options.send != 'never'
        myName = params.name
        myValue = params.value

        # if there are no values in a list, add a blank value so Rails knows all values were removed
        if Object.prototype.toString.call(params.value) == '[object Array]' && params.value.length == 0
          params.value.push("")

        obj = {}

        if nestedObj
          obj = build_nested_param(myName, myValue, nestedObj)
        else
          obj[myName] = myValue

        params[model] = obj

        delete params.name
        delete params.value
        delete params.pk

        $.ajax($.extend({
          url:      originalUrl
          data:     params
          type:     'PUT'
          dataType: 'json'
        }, @options.ajaxOptions))

    @saveWithoutUrlHook(value)

  EditableForm.prototype.saveWithoutUrlHook = EditableForm.prototype.save
  EditableForm.prototype.save = EditableForm.prototype.saveWithUrlHook
