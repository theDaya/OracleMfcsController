String.prototype.searchLike = function( searchValue ) {
  var 
    regexp = null,
    search = searchValue.toString();

/*
  if ( search.indexOf('%') != 0 ) {
    search = search + '%';
  }
  */

  if (searchValue.indexOf('%') > -1 ) {
    search = search.replace(/\./gi, '\\.');
    search = search.replace(/\(/gi, '\\(');
    search = search.replace(/\)/gi, '\\)');
    search = search.replace(/\[/gi, '\\[');
    search = search.replace(/\]/gi, '\\]');
    search = search.replace(/\{/gi, '\\{');
    search = search.replace(/\}/gi, '\\}');
    search = search.replace(/\?/gi, '\\?');
    search = search.replace(/\+/gi, '\\+');
    search = search.replace(/\*/gi, '\\*');
    
    //zamien % na zrozumiale w %
    search = search.replace(/%/gi, '.*');
    
    regexp = new RegExp( '^'+search+'$', "gi");

    return this.search( regexp );

  }
  else {
    return this.indexOf( searchValue );
  }

};


var isMSIE = /*@cc_on!@*/false;

jQuery.browser = {};
jQuery.browser.mozilla = /mozilla/.test(navigator.userAgent.toLowerCase()) && !/webkit/.test(navigator.userAgent.toLowerCase());
jQuery.browser.webkit = /webkit/.test(navigator.userAgent.toLowerCase());
jQuery.browser.opera = /opera/.test(navigator.userAgent.toLowerCase());
jQuery.browser.msie = /msie/.test(navigator.userAgent.toLowerCase());

/*
  selectors strings
*/

var 
  selector_pluginAjaxError = 'palv2_error',
  navigateCodes = ['40', '38', '37', '39', '35', '36', 40, 38, 37, 39, 35, 36],

  selector_popupContainer = 'palv2_popupContainer', //pluginPal2PopupContainer
  selector_popupAjaxContainer = 'palv2_popupAjaxContainer', //pluginPal2PopupContainerAjax
  selector_popupSearchNotFound = 'palv2_popupSearchNotFound', //'pal2_divSearchresultsNoFound',
  selector_popupSearchResults = 'palv2_popupSearchResults', //'pal2_divSearchresults',
  selector_popupSearchContainer = 'palv2_popupSearchContainer', //'pluginPal2PopupSearchBar',
  selector_popupFooterTr = 'palv2_popupFooterTr', //'pal2_popupFooterTr',
  selector_popupOuterContainer = 'palv2_popupOuterContainer', //'pal2_modalContainer',
  selector_popupSearchBox = 'palv2_popupSearchBox', //'pal2_divSearchBox',

  selector_promptAjaxContainer = 'palv2_promptAjaxContainer', //'pluginPal2AjaxContainer',

  selector_pastedNotFound = 'palv2_pastedNotFound', //'pal2_pastedNotFound',
  selector_popupSearchInput = 'palv2_popupSearchInput', //'pluginPal2PopupSearchInput',
  selector_popupMatchNotFound = 'palv2_popupMatchNotFound', //'not_found_ul',

  selector_pluginMask = 'palv2_pluginMask', //'plugin_pal2_mask',
  selector_pluginContainer = 'palv2_pluginContainer', //'plugin_pal_2',

  selector_iconPasted = 'palv2_iconPasted', //'plugin_pal2_pasted',
  selector_iconTrigger = 'palv2_iconTrigger', //'plugin_pal2_lov',
  selector_iconLoader = 'palv2_iconLoader', //'plugin_pal2_loader',
  selector_iconSingle = 'palv2_iconSingle', //'single',

  selector_iconMultiple = 'palv2_iconMultiple', //'multiple',
  selector_promptItemSelected = 'palv2_promptItemSelected', //'helper_selected',

  selector_iconHidden = 'palv2_iconHidden', //'hidden',
  selector_trEven = 'palv2_trEven', //'even',
  selector_trOdd = 'palv2_trOdd'; //'odd';


jQueryPAL(document).on('click', null, function(event){  
  var 
    helperDiv = jQueryPAL($x(selector_promptAjaxContainer)),
    input = jQueryPAL('#'+helperDiv.attr('item')+'_DISPLAY')
  
  input.trigger('removePrompt');
}).on('click', '.'+selector_iconPasted+', '+selector_pluginContainer+' .popover', function(event){
  event.stopPropagation();
}).on('click', '#'+selector_promptAjaxContainer+' tr:not(:has(th))', function(e){
  /*
    Gdy klikniecie na element listy z autofiltru
  */

  var 
    self = $(this),
    parentDiv = self.parents('#'+selector_promptAjaxContainer),
    mask = jQueryPAL(parentDiv.data('mask')),
    r = self.find('.return').text(),
    values = null,
    d = self.find('.display').text();

  if ( self.is('.selectAllValues') ) {
    values = jQueryPAL.map( parentDiv.find('.return'), function(elem, index){
      return $(elem).text();
    });

    mask.trigger('setValueFromPrompt', 
      {
        'display_value': parentDiv.find('.display').first().text(),
        'return_value': values.join( parentDiv.data('separator') )
      }
    );  

  }
  else {
    mask.trigger('setValueFromPrompt', {'display_value': d, 'return_value':r});  
  }
  
}).on('click', '#'+selector_promptAjaxContainer, function(event){
  event.stopPropagation();
}).on('mouseover', '#'+selector_promptAjaxContainer+' tr, #'+selector_popupAjaxContainer+' tr', function(){
  jQueryPAL(this).addClass('hover') 
  jQueryPAL('#'+selector_promptAjaxContainer+' .'+selector_promptItemSelected).removeClass(selector_promptItemSelected);
  
}).on('mouseout', '#'+selector_promptAjaxContainer+' tr, #'+selector_popupAjaxContainer+' tr', function(){
  jQueryPAL(this).removeClass('hover') 
});


function debounce(func, wait, immediate) {
	var timeout;
	return function() {
		var context = this, args = arguments;
		var later = function() {
			timeout = null;
			if (!immediate) func.apply(context, args);
		};
		var callNow = immediate && !timeout;
		clearTimeout(timeout);
		timeout = setTimeout(later, wait);
		if (callNow) func.apply(context, args);
	};
};

function palv2_init(id, p_optionsIn) {

  function padSpace(number) {
    var space = '';
    for (var i = 0; i <= number; i++)
      space +=' ';
    
    return space;
  }
/*
  function apexdebugstart(string) {
    apex.debug(padSpace(apexDebugSpace)+string);
    apexDebugSpace+=1;
  }
  
  function apexdebugend(string) {
    apexDebugSpace-=1;
    apex.debug(padSpace(apexDebugSpace)+string);
  }
*/  
  
  function displayErrorParseJSON( message ){
    var 
      error_id = native_item_id+'_POPUP_ERROR',
      popup_error = $('#'+error_id);
    
    popup_error.html( message).dialog('open');
  }
  
  function displayCustomError( ajax_return ){
    var 
      error_id = ajax_return.plugin.item_id+'_POPUP_ERROR',
      popup_error = $('#'+error_id);

    if (pluginObject.container.dialog('isOpen')) 
      pluginObject.container.dialog('close').data('ajax_return', ajax_return);
    
    popup_error.html( translations.PAELI_POPUP_NDF ).dialog('open');
  }
  
  function displayErrorFromAjax( ajax_return ){
    var 
      dialogErrorConfig = {
        autoOpen: false,
        draggable: false,
        maxHeight: 500,
        maxWidth: 600,
        minWidth: 'auto',
        dialogClass: selector_pluginAjaxError,
        title: label_text+' - ERROR',
        modal: true,
        create: function(){
          null;
        },
        open: function(){
          null;
        },
        close: function() {
          null;
        }
      },

      div = $(document.createElement('div')).attr({
        'class': selector_pluginAjaxError,
        'id': id+'_POPUP_ERROR'
      }).dialog( dialogErrorConfig ),    

      error_id = ajax_return.plugin.item_id+'_POPUP_ERROR',
      popup_error = $('#'+error_id);

    if (pluginObject.container != undefined && pluginObject.container.dialog('isOpen')) 
      pluginObject.container.dialog('close').data('ajax_return', ajax_return);
    
    popup_error.html(
      '<table>'
        +'<tr>'
          +'<td>Item:</td> <td>'+ ajax_return.plugin.item_id +' ('+ ajax_return.plugin.plain_label +')</td>'
        +'</tr>'      
        +'<tr>'
          +'<td>Function:</td> <td>'+ ajax_return.error.func_name +'</td>'
        +'</tr>'      
        +'<tr>'
          +'<td>Mode:</td> <td>'+ ajax_return.error.mode +'</td>'
        +'</tr>'      
        +'<tr>'
          +'<td>Error message:</td> <td> <pre>'+ ajax_return.error.SQLERRM +'</pre></td>'
        +'</tr>'      
      +'</table>'
    ).dialog('open');
  }


  function _plugin_set_value( value ) {
    plugin.val( value );
  }

  function _plugin_get_value( value ) {
    return plugin.val();
  }
  
  
  function _mask_set_value( value ) {
    mask.val( value );
  }
  
  function _mask_set_data(data) {
    mask.data(data);
  }
  
  function _mask_reset_data(){
    _mask_set_data({
      pasted_values: [],
      single_value: null,
      eventPaste: false
      
    });
  }

  function _mask_get_value(){
    return mask.val();
  }
  
  function _popover_content(){
    var 
      icon = iconPaste
      values = mask.data('pasted_values'),
      td2copy = $(document.createElement('td')),
      tr2copy = $(document.createElement('tr')),
      temp_td = (td2copy.clone(false)).text('No. of pasted values: '+values.length),
      temp_tr = (tr2copy.clone(false)).append(temp_td),
      table = $(document.createElement('table')).append(temp_tr);

    for (i in values) {
      temp_td = (td2copy.clone(false)).text(''+values[i]);
      temp_tr = (tr2copy.clone(false)).addClass( i%2==0 ? selector_trEven : selector_trOdd ).append( temp_td );
      
      table.append( temp_tr );
    }
    
    return table.html();
  }

  function _icon_loading_show(){
    iconLoading.removeClass(selector_iconHidden);

    apex.event.trigger( plugin, 'paeli_icon_loading_show')
  }

  function _icon_loading_hide(){
    iconLoading.addClass(selector_iconHidden);
    apex.event.trigger( plugin, 'paeli_icon_loading_hide')
  }

  function _icon_trigger_show(){
    iconTrigger.removeClass(selector_iconHidden);
    apex.event.trigger( plugin, 'paeli_icon_trigger_show')
  }

  function _icon_trigger_hide(){
    iconTrigger.addClass(selector_iconHidden);
    apex.event.trigger( plugin, 'paeli_icon_trigger_hide')
  }

  function _icon_trigger_reset() {
    iconTrigger.removeClass('empty green red '+selector_iconSingle+' '+selector_iconMultiple);
    apex.event.trigger( plugin, 'paeli_icon_trigger_hide');
  }
  
  function _icon_trigger_single(){
    _icon_trigger_reset();
    
    iconTrigger.addClass( selector_iconSingle );
    apex.event.trigger( plugin, 'paeli_icon_trigger_single');
  }

  function _icon_trigger_single_matched(){
    _icon_trigger_reset();
    
    iconTrigger.addClass( selector_iconSingle ).addClass('green');
    apex.event.trigger( plugin, 'paeli_icon_trigger_single_matched');
  }
  
  
  function _icon_trigger_multiple(){
    _icon_trigger_reset();
    
    iconTrigger.addClass( selector_iconMultiple );
    apex.event.trigger( plugin, 'paeli_icon_trigger_multiple');
  }

  function _icon_trigger_multiple_matched(){
    _icon_trigger_reset();
    
    iconTrigger.addClass( selector_iconMultiple ).addClass('green');
    apex.event.trigger( plugin, 'paeli_icon_trigger_multiple_matched');
  }
  
  
  function _icon_paste_show(){
    iconPaste.removeClass(selector_iconHidden);
    //iconPaste.popover('show');
    apex.event.trigger( plugin, 'paeli_icon_paste_show');
  }

  function _icon_paste_hide(){
    iconPaste.addClass(selector_iconHidden);
    iconPaste.popover('hide');
    apex.event.trigger( plugin, 'paeli_icon_paste_hide');
  }
  
  function _setPopover(){
    var popoverOptions = {
      'html': true,
      'placement': 'right',
      'trigger': 'click',
      'title': 'Pasted values',
      'content': _popover_content,
      'container': 'body' //podmieniane na self
    };

    popoverOptions.container = item_container;
    iconPaste.popover( popoverOptions );
  }
  
  function _copy_plugin_value_2_mask(){
    _mask_set_value( _plugin_get_value().split( separator )[0] );
  }


  function __respone_isError(ajax_return){
    if (ajax_return.error.error == 1 || ajax_return.error.error == '1') {
      return true;
    }
    
    return false;
  }
  
    
  function _set_popups(){

    function dialogConfig_showSelected() {
      var 
        id = native_item_id+'_show_selected',
        container = $( document.createElement('div') ).attr('class', 'palv2_divShowSelected'),
        checkbox = null;

      checkbox = $( document.createElement('input') ).attr({
          'type': 'checkbox',
          'id': id
      }).bind('change', function(){
        var 
          self = $(this),
          selectedArray;
        
        pluginObject.data.handlers.inputSearch.val( null );
        
        if ( self.is(':checked') ) {
          self.prop('checked', pluginObject.data.showSelected() );
        }
        else {
          pluginObject.data.handlers.checkboxSelectAll.prop('checked', false);
          pluginObject.data.showAll();
        }
        
        pluginObject.data.isShowSelected = self.is(':checked');
      });

      container.append( checkbox ).append( '<label for="'+id+'">'+translations.PAELI_POPUP_SHOW_SELECTED+'</label>' );
      
      return container;
    }

    function dialogConfig_search(){
      var 
        searchBoxContainer = jQueryPAL(document.createElement('div')).attr('class', selector_popupSearchContainer),
        div_searchBox = jQueryPAL(document.createElement('div')).attr('class', 'searchboxDiv'),
        inputSearchIcon = jQueryPAL(document.createElement('span')).addClass('ui-icon ui-icon-search'),
        inputSearchLoading = jQueryPAL(document.createElement('i')).addClass('palv2_iconLoader palv2_iconHidden').css('margin-left', 5),
        inputSearch = jQueryPAL(document.createElement('input'));

      inputSearch.dblclick(function(){
        //console.log( pluginObject );
      })
      
      inputSearch.attr('type', 'text').keyup( function(){
        var self = $(this);
        self.next('.palv2_iconLoader').removeClass('palv2_iconHidden');
        pluginObject.data.resetMoreSet();
        pluginObject.data.clear();

      } );
      inputSearch.attr('type', 'text').keyup( debounce(function(){
        var 
          self = $(this),
          search_string = self.val();
        
        pluginObject.data.render( pluginObject.data.find( search_string ) );

        self.next('.palv2_iconLoader').addClass('palv2_iconHidden');
      }, 600) );
      
      div_searchBox.append( inputSearchIcon ).append( inputSearch ).append( inputSearchLoading );
      searchBoxContainer.append(div_searchBox);
      
      return searchBoxContainer;
    }

    function dialogConfig_selectAll() {
      var 
        container = jQueryPAL(document.createElement('div')).attr('class', 'palv2_divSelectAll'),
        checkboxId = native_item_id+'_select_all';
      
      var checkbox = $(document.createElement('input')).attr({
        'id': checkboxId,
        'type': 'checkbox',
        'class': 'pal2_popupSelectAllVisible',
        'for': 'popupValues'
      }).bind('change', function(){
        var 
          self = $(this),
          selfStatus = self.is(':checked'),
          result = pluginObject.data.changeStatusAll( selfStatus );
        
        self.prop('checked', selfStatus && result ? true : false)
        
        //pluginObject.data.isSelectAll = self.is(':checked');
      });
      


      container.append( checkbox ).append(' <label for="'+checkboxId+'">'+translations.PAELI_POPUP_SELECT_ALL+'</label>');
      
      return container;
    }

    function dialogConfig_create() {
      var 
        self = jQueryPAL(this),
        //buttonContainer = self.next(),
        buttonContainer = self.nextAll('.ui-dialog-buttonpane'),
        
        headerContainer = $( document.createElement('div') ).attr('class', 'palv2_tableHeaderContainer').append( dialogConfig_search() );
      
      

      self.on('change', ':radio', function(){
        var 
          rownum = $(this).attr('rownum'),
          checked = $(this).is(':checked');

        //pluginObject.data.deselectAllSelected();
        pluginObject.data.deselectAll();
        pluginObject.data.changeStatus( rownum, checked );        
      }).on('change', ':checkbox', function(){
        var rownum = $(this).attr('rownum');
        pluginObject.data.changeStatus( rownum, $(this).is(':checked') );
      }).on('mouseover', 'tr', function(){
        $(this).addClass('hover');
      }).on('mouseout', 'tr', function(){
        $(this).removeClass('hover');
      }).before( headerContainer );
      
      if (options._multiple == 'Y')
        headerContainer.append( dialogConfig_selectAll() );
      
      buttonContainer.append( dialogConfig_showSelected() );
      
    }

    function dialogConfig_open() {
      pluginObject.container.data('btnClick', false);
      apex.event.trigger( plugin, 'plugin_popup_opened');
      $('body').css('overflow', 'hidden');
    }

    function dialogConfig_close() {
      var 
        popup = jQueryPAL( iconTrigger.data('popup') ),
        popupParent = popup.parent(); 

      
      
      popupParent.find($x_ByClass( selector_pastedNotFound) ).addClass( selector_iconHidden );
      popupParent.find($x_ByClass( selector_popupSearchResults) ).text('');
      popupParent.find($x_ByClass( selector_popupSearchInput) ).val('');
      
      pluginObject.data.deselectAll();        

      $('body').css('overflow', 'auto');

      if ( pluginObject.container.data('btnClick') ) {
        apex.event.trigger( plugin, 'plugin_popup_close_btn');
      }
      else {
        apex.event.trigger( plugin, 'plugin_popup_close');
      }

      
    }

    function dialogConfig_btn_click(){
      var 
        firstObjectSelected = [],
        resultString = '',
        selectedValuesArray = [];
      
      selectedValuesArray = pluginObject.data.getCheckedValues();
      resultString = selectedValuesArray.join( separator );
      
      if ( resultString.length > options._maxChars) {
        alert( (translations.PAELI_POPUP_LENGTH).replace('#limit#', options._maxChars) );
        return false;
      }  
      else {
        
        if ( resultString.length > 0 ) {
          firstObjectSelected = pluginObject.data.getFirstSelectedObject();  
          _plugin_set_value( resultString );
          _mask_set_value( firstObjectSelected.d );
        }
        else {
          _plugin_set_value( null );
          _mask_set_value( null );
          
        }
        
        _icon_paste_hide();
        
        pluginObject.container.data('btnClick', true);
        pluginObject.container.dialog('close');
        plugin.trigger('change', [true]);
      }
      
      return void(0);      
    }

    var  
      dialogConfig = {
        'autoOpen': false,
        'minHeight': 300,
        'height': 'auto',
        'maxHeight': $(window).outerHeight()*0.9,
        'minWidth': 450,
        'title': label_text+translations.PAELI_POPUP_SUFIX,
        'dialogClass': selector_popupOuterContainer,
        'modal': true,
        'create': dialogConfig_create,
        'open': dialogConfig_open,
        'buttons': [
          {
            text: translations.PAELI_BTN_SELECT,
            click: dialogConfig_btn_click
          }
        ],
        'close': dialogConfig_close
      },
      popupContainer = $(document.createElement('div')).attr({
        'id': id+'_POPUP'
      }),
      popupContainerAjax = $(document.createElement('div')).attr({
        'class': selector_popupAjaxContainer
      });
    
    popupContainer.bind('scroll', debounce(
      function(e){
        var 
          container = $(e.currentTarget),
          table = container.find('table').first(),
          tableBottomLimit = table.outerHeight(),
          calculatedScrollToBottom = Math.abs(table.offset().top) + container.height() + container.offset().top;
        
        if ( calculatedScrollToBottom + 200 >=  tableBottomLimit) {
          pluginObject.data.renderMore();
        }
      }, 200
    )).append( popupContainerAjax ).dialog( dialogConfig );
    
    //do wywalenia - refactoring
    iconTrigger.data('popup', popupContainer);
    
    pluginObject.container = popupContainer;
    pluginObject.popupAjaxContainer = popupContainerAjax;
  }

  function ajaxData(reqOptions) {
    var lData = { 
      p_request: "NATIVE="+options.ajaxIdentifier,
      p_flow_id: $v('pFlowId'),
      p_flow_step_id: $v('pFlowStepId'),
      p_instance: $v('pInstance'),
      x01: reqOptions.mode,
      x02: reqOptions.search
    };

    $(options.dependingOnSelector+','+options.pageItemsToSubmit).each(function(){
      var lIdx;
      if (lData.p_arg_names===undefined) {
        lData.p_arg_names  = [];
        lData.p_arg_values = [];
        lIdx = 0;
      } 
      else {
        lIdx = lData.p_arg_names.length;
      }
      
      lData.p_arg_names [lIdx] = this.id;
      lData.p_arg_values[lIdx] = $v(this);
    });

    
    return lData;
  }
    
  function _ajax_set_current_request( ajaxObj ){
    plugin.data('ajax_handler', ajaxObj);
  }
  
  function _ajax_abort_previous(){
    var xhr = plugin.data('ajax_handler') == undefined ? null : plugin.data('ajax_handler');
    
    if (xhr != null) {
      xhr.abort();
    }
    
    _icon_loading_hide();
    _icon_trigger_show();
  }
  
  function force_refresh_parent() {
    _cleanPlugin();
    _ajax_abort_previous();
    _icon_loading_show();
    _icon_trigger_hide();
    
    var dataOptions = {
      mode: 'forceRefresh',
      search: null
    }
    
    plugin.trigger('apexbeforerefresh');

    var xhr = $.ajax({
      url:'wwv_flow.show',
      type:'post',
      dataType:'json',
      traditional: true,
      data: ajaxData(dataOptions),
      success: function(){ 
        _icon_loading_hide();
        _icon_trigger_show();
        plugin.trigger('apexafterrefresh');
      }
    });
    
    _ajax_set_current_request( xhr )
  }

   function _cleanPlugin() {
    iconTrigger.removeClass(selector_iconMultiple).removeClass(selector_iconSingle);
    
    _mask_set_value( null )
    
    _plugin_set_value(null);
    _mask_reset_data();
    _icon_paste_hide()
  }
  
  function _set_paste(){
    if ( options._allowPaste == 'Y' ) {
      if (isMSIE) {
        mask.bind('paste', _e_mask_paste);
      }
      else {
        mask.catchpaste( _e_mask_paste );
      }
    }
  }
  
  function _set_mask() {

    function ajax_response( data ){ 
      if ( __respone_isError(data) ) {
        _icon_loading_hide();
        _icon_trigger_show();
        _copy_plugin_value_2_mask();
        _e_real_event_change();
          
        return void(0);
      }
    
      _icon_loading_hide();
      _icon_trigger_show();


      _mask_set_value( data.values[0].d );

      if ( valuesBeforeMask.length > 1 ) {
        if (options._multiple == 'N') {
          _plugin_set_value( data.values[0].r );
        } 
        else {
          _plugin_set_value( valuesBeforeMask.join( separator ) );    
        } 
        
      }
      else {
        _plugin_set_value( data.values[0].r );  
      }
      
      //tu powinna isc informacja ze maska jest dopasowana lub nie
      apex.event.trigger( plugin, 'plugin_init_retrieve_mask')
      _e_real_event_change( null, data.values[0].matched );
    }

    var 
      valuesBeforeMask = _plugin_get_value().split( separator ),
      firstValue = (_plugin_get_value().split( separator ))[0],
      xhr = plugin.data('ajax_handler') == undefined ? null : plugin.data('ajax_handler'),
      dataOptions = {
        'mode': 'getMask',
        'search': firstValue
      };

    _icon_loading_show();
    _icon_trigger_hide();
    
    if ( $.inArray(firstValue, [null, undefined, '']) > -1 ) {
      _icon_loading_hide();
      _icon_trigger_show();
      
      _copy_plugin_value_2_mask();      
      
      return void(0);
    }
    
    if (xhr != null) {
      xhr.abort();
    }
    
    xhr = $.ajax({
      url:'wwv_flow.show',
      type:'post',
      dataType:'json',
      traditional: true,
      success: ajax_response,
      data: ajaxData(dataOptions)
    }); 
    
    plugin.data('ajax_handler', xhr);
    
  }
  
  function _e_real_event_change(event, is_data_matched) {
    var 
      values = _plugin_get_value().split( separator ),
      matched = false,
      multiple = false,
      itemObject = {},
      eventObject = {};

    //nie ma obslugi gdy 0, bo split z pustego stringa z danym separatorem zwraca tablice jednoelementowa
    if ( values.length == 1 ) { //wartości jest jedna i i nie jest pusta

      if ( values[0] != '' ) {
        if (is_data_matched) {
          _icon_trigger_single_matched();
          matched = true;
          multiple = false;
        }
        else {
          _icon_trigger_single();
          matched = false;
          multiple = false;
        }
      }
      else { //wybrano 0 checkboxów z popup, czyl iresetowanie wartości
        _icon_trigger_reset();      
        matched = null;
        multiple = null;
      }
    }
    else { //wartości jest wiecej niz jedna ( values.length > 1 )
      if (is_data_matched) {
        _icon_trigger_multiple_matched();
        matched = true;
        multiple = true;

      }
      else {
        _icon_trigger_multiple();
        matched = false;
        multiple = true;
      }
    }

    itemObject = _plugin_trigger_data();

    eventObject = {
      'PAELI': {
        'changedMultiple': multiple,
        'changedMatched': matched
      }
    };
    
    apex.event.trigger( plugin, 'plugin_value_changed', $.extend(true, itemObject, eventObject) );
  }  

  function _plugin_trigger_data( p_helper ){
    return {
      PAELI: {
        "mask": {
          "item": mask,
          "id": native_item_id+'_DISPLAY',
          "value": _mask_get_value(),
          "helper": p_helper
        },
        "apexItem": {
          'item': plugin,
          "id": native_item_id,
          "value": _plugin_get_value(),
          "container": item_container
        },
        "label": {
          "reference": label,
          "text": label_text
        }
      }
    };
  }

  
  function _getClipBoardAsArray2D(source) {
    var schowek = $.trim(source);
    
    schowek=schowek.replace(/\t/gi, "\t ");
    var wiersze = schowek.split(/\n/gi);
    
    var clipBoard = [];
    
    var liczba_wierszy = wiersze.length;
    var liczba_kolumn = wiersze[0].split(/\t/gi).length;
    
    for (var x = 0; x < liczba_wierszy ; x++) {
      clipBoard[x] = [];
      for (var y = 0; y < liczba_kolumn ; y++) {
        clipBoard[x][y] = null;
      }
    }

    for(var x=0;x<wiersze.length;x++){
      var kolumny = wiersze[x].split(/\t/gi);
      for(var y=0;y<kolumny.length;y++){
        clipBoard[x][y] = $.trim(kolumny[y]);
      }
    }  
    return clipBoard;
  }
  
  function _e_mask_paste(paste) {
    
    iconPaste.popover('hide');
    var input_text = jQueryPAL(this);
    var table2d = [];
    
    mask.data('eventPaste', true);
    
    table2d = isMSIE ? _getClipBoardAsArray2D(window.clipboardData.getData("Text")) : _getClipBoardAsArray2D(paste);
    
    if ( table2d.length > 0 ) {
      mask.val(null);
    }
    
    var new_arr = [];
    
    for (i in table2d) {
      new_arr.push(table2d[i][0]);
    }
    
    var table2d_string = new_arr.join( separator );
    
    if ( table2d_string.length > options._maxChars) {
      
      if (!confirm( (translations.PAELI_PASTED_LENGTH).replace('#limit#', options._maxChars) )) {
        _mask_reset_data();
        _mask_set_value(null);
        mask.trigger('change');
        
        return null;
      }
      new_arr = finalString( table2d_string ).split( separator );
      iconPaste.popover('hide');
    }
    
    _mask_set_data( {'pasted_values': new_arr } );
    _mask_set_value( new_arr[0] );

    if (new_arr.length == 1) {
      
      if (options._autofilter == 'Y') {
        mask.data('eventPaste', false);
        mask.trigger('change');  
        mask.trigger('keyup');
      }
      else {
        _icon_paste_show();
        mask.trigger('change');  
      }
    }
    else {
      _icon_paste_show();
      mask.trigger('change');  
    }
    
    
    
    
    
    return null;
  }
 
  function _e_mask_change(){    
    
    
    
    if (jQueryPAL('#'+selector_promptAjaxContainer+':has(table)').size()>0) {
      
      return false;
    }
    
    if (mask.data('pasted_values').length == 0 ) {
      //apex.debug('PAELI - mask - event "change" - na data pasted, hide icon paste');
      _icon_paste_hide();
    }
    
    if (mask.data('pasted_values').length > 0 ) {
      //apex.debug('PAELI - mask - event "change" - set pasted values');
      plugin.val( mask.data('pasted_values').join( separator ) );
    }
    
    else if ( mask.data('single_value') != null) {
      //apex.debug('PAELI - mask - event "change" - single value');
      plugin.val( mask.data('single_value') );
      //apex.debug('PAELI - mask - event "change" - plugin set value = "'+mask.data('single_value')+'"');
    }
    else {
      //apex.debug('PAELI - mask - event "change" - mask changed manually');
      plugin.val( mask.val() );
    }
    
    apex.event.trigger(plugin, 'change',false);
    
  }  
  
  
  function _ajax_helper_create(){
    var divContainer = $(document.createElement('div'));

    divContainer.attr({
      'id': selector_promptAjaxContainer,
      'item': id
    }).data({
      'mask': jQueryPAL(mask),
      'separator': separator
    }).css({
      'min-width': mask.outerWidth(),
      'max-width': ($(window).outerWidth()-mask.offset().left)*0.9,
      'top': mask.offset().top+mask.outerHeight(),
      'left': mask.offset().left

    });
    
    return divContainer;
  }
  
  function _ajax_mask_autofilter_callback(data) {

    var 
      divContainer = _ajax_helper_create(),
      ajax_return = data,   
      input = mask,
      //mustache templates
      template = '',
      template_header = '',
      template_footer = '',
      return_col = options._returnCollumn,
      select_all_td = '<tr class="selectAllValues"><td'+ (return_col == 'Y' ? ' colspan="2"' : '') +'> '+translations.PAELI_SELECT_ALL_AUTOFILTER+' </td></tr> ',
      output = null,
      selected = null;
    
    if (ajax_return.error.error == 1 || ajax_return.error.error == '1') {
      displayErrorFromAjax( ajax_return );
      return false;
    }
    else {
      
      if ( ajax_return.values.length == 0 ) {
        template = '<span class="no-data-found">'+translations.PAELI_AUTOFILTER_NDF+' "<i>'+(ajax_return.input.p_search)+'</i>"<span>';
      }
      else {

        template_header = '<table cellspacing="0" cellpadding="0">';//'<table cellspacing="0" cellpadding="0">'+(return_col == 'Y' ? '<tr><th>Return</th><th>Display</th></tr>' : '');
        template_header += ( ajax_return.autofilter.searchMultiple == true ? select_all_td : '' );

        template = Mustache.render(''
          +'{{#values}}'
          +'  <tr>'
          +     '<td class="return" '+( return_col == 'Y' ? '' : 'style="display:none"')+'>{{r}}</td>'
          +'    <td  class="display">{{d}}</td>'
          +'  </tr>'
          +'{{/values}}', ajax_return);
          
        template_footer = '</table>';
      }
      output = '<div>'+template_header+template+template_footer+'</div>';
    }
    
    divContainer.html( output );
    
    selected = divContainer.find('.selectAllValues').size() == 0 ? divContainer.find('tr').first('not:has(th)') : divContainer.find('.selectAllValues');
    selected.addClass('hover');
    
    _ajax_helper_remove();
    _ajax_helper_add( divContainer );
    
    mask.data({
      'prompt': divContainer,
      'selected': selected
    });
    
    _icon_loading_hide();
    _icon_trigger_show();
  }    
  
  function _ajax_helper_add( elem ){
    //item_container.append( elem );
    var body = $('body');
    elem = body.append( elem ).find( elem );

    elem.css({
      'maxHeight': elem.find('.no-data-found').size() > 0 ? elem.find('.no-data-found').outerHeight() :  elem.find('tr').first().outerHeight()*5
    });

    apex.event.trigger( plugin, 'plugin_helper_poped', _plugin_trigger_data( elem ));
  }
  
  function _ajax_helper_remove(){
    $('body').find('#'+selector_promptAjaxContainer).remove();
  }
 
  
  function _e_mask_keypress(e){
    
    
    
    e.stopPropagation();
    
    if ( e.keyCode != 13 ) {

      
      return void(0);
    }
     
    //wykryto enter wiec przetwarzamy dalej
    if ( jQueryPAL($x( selector_promptAjaxContainer )).is(':has(table)') ) {
      var selected = jQueryPAL(mask.data('selected'));
      var parentDiv = jQueryPAL(mask.data('prompt'));
      var values = null;

      if ( selected.is('.selectAllValues') ) {
        values = jQueryPAL.map( parentDiv.find('.return'), function(elem, index){
          return $(elem).text();
        });

        mask.trigger('setValueFromPrompt', 
          {
            'display_value': parentDiv.find('.display').first().text(),
            'return_value': values.join( parentDiv.data('separator') )
          }
        );  

      }
      else {
        mask.trigger('setValueFromPrompt', {
          display_value: selected.find('.display').text(),
          return_value: selected.find('.return').text()
        });
      }      
      
      return void(0);
      
    }
    else {
      if ( options._submitPage == 'Y' ){
        apex.submit({request: id, showWait: (options._showProcessing == 'Y') });
      }
      else {
        
        return false;
      }
    }

    
    
  }

  function _ajax_mask_autofilter(){

    if (options._autofilter == 'N') {
      return void(0);
    }
    
    _ajax_abort_previous();
    _icon_loading_show();
    _icon_trigger_hide();
    
    var dataOptions = {
      mode: 'autofilter',
      search: _mask_get_value()
    }
    
    var xhr = $.ajax({
      url:'wwv_flow.show',
      type:'post',
      dataType:'json',
      traditional: true,
      data: ajaxData(dataOptions),
      error: function( jqXHR, textStatus, errorThrown ){
        if (textStatus == 'abort') {
          return void(0);
        }
        _icon_loading_hide();
        _icon_trigger_show();
        
        displayErrorParseJSON('Autofilter error: ('+textStatus+') '+errorThrown);
        
      },
      success: function( ajax_return ){ 
        _icon_loading_hide();
        _icon_trigger_show();
        
        _ajax_mask_autofilter_callback( ajax_return );
      }
    });
    
    _ajax_set_current_request( xhr );
  }
  
  function _mask_is_prompt(){
    if ( mask.data('prompt') == null || mask.data('prompt') == undefined ) {
      return false;
    }
    
    return true;
  }
  
  function _e_mask_removePrompt(does_mas_change){
    
    $(mask.data('prompt')).remove();
    mask.data( {'prompt': null, 'selected': null} );
    
    if (does_mas_change) {
      //apex.debug('PAELI - mask - event "removePrompt" - trigger mask change');
      mask.trigger('change');
    }
    //czy tu powinien byc trigger?
    apex.event.trigger( plugin, 'plugin_helper_removed');
    
    
  }
  
  function _e_mask_kayup(e) {
    
    if (mask.data('eventPaste') ) {
      //apex.debug('PAELI - mask - event "keyup" - event paste in progress');
      
      if ( e.keyCode == 17 ) {
        mask.data( {'eventPaste': false} );
        
        
        return false;
      
      }
      return false;
    }

    if ( e.keyCode == 17 ) {
      mask.data( {'ctrl': false});

      if (mask.data('selectAll')) {
        mask.data('selectAll', false);  
        return false;
      }
    }
    //select all
    if ( e.keyCode == 65 && mask.data('ctrl')) {
      mask.data('selectAll', true);
      return false;
    }
    
    
    mask.data({
      'eventPaste': false,
      'pasted_values': [],
      'single_value': _mask_get_value()
    });
    
    //_icon_paste_hide();
  
    if ( $.inArray(e.keyCode, navigateCodes) > -1 ) {
      
      
      return false;
      
    }
    else {
      
      if ( e.keyCode == 8 ) {
        //apex.debug('PAELI - mask - event "keyup" - (backspace)');
        _ajax_abort_previous();
      }
      
      else if ( e.keyCode == 13 ) {
        //apex.debug('PAELI - mask - event "keyup" - END (enter)');
        return void(0);
      }
      
      else if ( e.keyCode == 27 ) {
        _e_mask_removePrompt();
        _ajax_abort_previous();
        //apex.debug('PAELI - mask - event "keyup" - END (escape)');
        return void(0);
      }
      
      if ( _mask_get_value().length == 0 ) {
        //apex.debug('PAELI - mask - event "keyup" - 0 length -> removePrompt');
        
        _e_mask_removePrompt();
      }
      else {
        _e_mask_removePrompt();
        _ajax_mask_autofilter();
      }
    
  
    }
    
    
  }

  function _mask_prompt_navigateDown( elem ) {
    var 
      nextElem = null,
      prompt = $(mask.data('prompt')),
      tr_height = prompt.find('tr').first().outerHeight();
    
    
    if (elem == null || elem == undefined) {
      elem = $('tr:not(:has(th)):first', prompt );
    }
    else {
      elem = $(elem);
    }
    
    if (elem.is('.hover')) {
      nextElem = elem.next();

      if (nextElem.size() == 0) {
        
        nextElem = $(elem.prevAll(':not(:has(th)):last')).size() == 0 ? elem : $(elem.prevAll(':not(:has(th)):last'));
        
      }
      
      prompt.scrollTop( nextElem.prevAll(':not(:has(th))').size()*tr_height );
      
      elem.removeClass('hover');
      nextElem.addClass('hover');
      
      mask.data('selected', nextElem);
    }
    else {
      elem.addClass('hover');
      mask.data('selected', elem);
    }
  }
  
  function _mask_prompt_navigateUp( elem ) {
    var nextElem = null;
    var prompt = $(mask.data('prompt'));
    
    var tr_height = prompt.find('tr').first().outerHeight();
    
    if (elem == null || elem == undefined) {
      elem = $('tr:last', prompt );
    }
    else {
      elem = $(elem);
    }
    
    if (elem.is('.hover')) {
      nextElem = elem.prev(':not(:has(th))');

      if (nextElem.size() == 0) {
        nextElem = $(elem.nextAll(':last')).size() == 0 ? elem : $(elem.nextAll(':last'));
      }
      
      prompt.scrollTop( nextElem.prevAll(':not(:has(th))').size()*tr_height );
      elem.removeClass('hover');
      nextElem.addClass('hover');
      
      mask.data('selected', nextElem);
    }
    else {
      elem.addClass('hover');
      mask.data('selected', elem);
    }
  }  
  
  /*
    funkcja _e_mask_kaydown
    przeznaczenie: wychwytwanie czy został wciśnięty klawisz enter, oraz do obsługi nawigacji via strzałki
  */
  function _e_mask_kaydown(e) {
    
    if ( e.keyCode == 17 ) {
      mask.data('ctrl', true);
      
    }

    //apex.debug('PAELI - mask - event "keydown" - START');
    
    if ( $.inArray(e.keyCode, [13, 9]) < 0 && $.inArray(e.keyCode, navigateCodes) < 0 ) {
      //apex.debug('PAELI - mask - event "keydown" - END (nothing to do)');
      return void(0);
    }
    
    if ( e.keyCode == 9 ) {
      mask.trigger('removePrompt');
    }
    if ( e.keyCode == 13 ) {
      e.preventDefault();
      //
      //if (!$.browser.mozilla) {
        _e_mask_keypress(e);
      //}
    }
    
    if ( $.inArray(e.keyCode, navigateCodes) > -1 ) {

      if ( _mask_is_prompt() ) {
        if ( e.keyCode == 38 ) {
          _mask_prompt_navigateUp( mask.data('selected') );
          
        }
        else if ( e.keyCode == 40 ) {
          _mask_prompt_navigateDown( mask.data('selected') );
        }
        
      }
      else {
        //nie ma prompt
        if ( _mask_get_value().length != 0 ) {
          _ajax_mask_autofilter();
        }
      }
    }
    //apex.debug('PAELI - mask - event "keydown" - END');
  }


  function getAllMask(e, data){
    var 
      fakePluginData = data,
      dataOptions = {
        mode: 'getAllMask',
        search: data.values
      },
      xhr = null;

    xhr = $.ajax({
      url:'wwv_flow.show',
      type:'post',
      dataType:'json',
      traditional: true,
      success: function(data){ 
        
        data.columnName = fakePluginData.columnName;

        $( fakePluginData.region ).first().trigger('setAllMask', data);
        return void(0);

      },
      data: ajaxData(dataOptions)
    });
    
    plugin.data('ajax_handler', xhr);
  }

  function _parse_JSON( json2parse ) {
    
    var parsedJSON = null;
    
    try {
      parsedJSON = $.parseJSON( json2parse );
      
    } catch(error) {
      displayErrorParseJSON('While parsing JSON response error occured: '+error);
      return false;
    }
    
    if ( parsedJSON.error.error == 1 || parsedJSON.error.error == '1') {
      displayErrorFromAjax( parsedJSON );
      return false;
    }
    
    if (parsedJSON.error.error == 2 || parsedJSON.error.error == '2') {
      displayCustomError( parsedJSON );
      return false;
    }
    
    return parsedJSON;
    
  }

  function _extendPopuplovObj( object ){
    
    var container = $('#'+native_item_id+'_POPUP');
    var popupHeaderDiv = container.prev();
    
    object.searchString = '';
    
    object.selected = 0;
    object.handlers = {
      'popupHeaderDiv': popupHeaderDiv,
      'resultContainer': container.find('[class='+selector_popupAjaxContainer+']'),
      'inputSearch': popupHeaderDiv.find('.searchboxDiv :input'),
      'checkboxSelectAll': popupHeaderDiv.find('[id*=_select_all]'),
      'labelSelectAll': popupHeaderDiv.find('label[for*=_select_all]'),
      'checkboxShowSelected': container.parent().find('[id*=_show_selected]'),
      'labelShowSelected': container.parent().find('[for*=_show_selected]'),
    };
    
    
    object.find = function(search){
      var self = this;
      var temp = null;
      var isShowSelected = this.isShowSelected

      search = search.toUpperCase();
      this.searchString = search;
      temp = $(self.values).filter(function(index, value){
        
        if ( isShowSelected == true && value.checked != true) {
          return false;
        }

        //return value.r.toUpperCase().indexOf(search) > -1 || value.d.toUpperCase().indexOf(search) > -1;


        if ( options._returnCollumn == 'Y' )
          return value.r.toUpperCase().searchLike(search) > -1 || value.d.toUpperCase().searchLike(search) > -1;
        else {
          return value.d.toUpperCase().searchLike(search) > -1;
        }
        
      });
      
      this.showAllCount( temp.length );
      
      return $.makeArray(temp);
    }

    object.getFirstSelectedObject = function(){

      var firstSelected = null;
    
      for ( var i=0, length = this.values.length; i < length; i++ ) {
        if ( this.values[i].checked ) {
          firstSelected = this.values[i];
          break;
        }
      }
      
      return firstSelected;
      
    }
    
    object.selectByValue = function( value ) {
      value = value.toUpperCase();
      
      for (var i=0, length = this.values.length; i < length; i++) {
        if ( this.values[i].r.toUpperCase() == value || this.values[i].d.toUpperCase() == value ) {
          this.values[i].checked = true;
          this.calculateSelected( true );

        }
      }
    }
    
    

    object.selectFromPlugin = function(){
      var array = plugin.val().split( separator );
      
      for ( var i=0, length = array.length; i < length; i++ ) {
        this.selectByValue( array[i] );
        
      }
      
    };
    
    object.calculateSelected = function(status){
      if (status)
        this.selected += 1;
      else
        this.selected -= 1;
    }
    
    object.resetMoreSet = function() {
      this.more2render = [];
    }

    object.renderMore = function(){
      if ( this.more2render.length > 0 ) 
        this.render( this.more2render );
    }

    object.deselectAll = function() {
      for ( var length = this.values.length, i=0; i < length; i++ ) {
        this.values[i].checked = false;
      }
      
      this.selected = 0;
      this.handlers.inputSearch.val(null);
      this.handlers.checkboxSelectAll.prop('checked', false);
      this.showSelectedCount();
    }
    
    
    object.deselectAllSelected = function() {
      for ( var length = this.values.length, i=0; i < length; i++ ) {
        if ( this.isShowSelected ) {
          this.values[i].checked = false;
          this.calculateSelected( false );
        }
      }
    }
    
    object.changeStatusAll = function(status){
      
      //var currentLength = $.makeArray( this.getChecked() ).length;
      var currentLength = this.getArrayLength( $.makeArray( this.getChecked() ) );
      var destSelectedLength = 0;
      var resultArrayRender = [];
      
      if ( this.hasOwnProperty('searchString') && this.searchString.length > 0 ) {
        destSelectedLength = this.getArrayLength( this.find( this.searchString ) );
        
        if ( status && currentLength + destSelectedLength > options._maxChars ) {
          if ( !confirm( (translations.PAELI_SELECT_ALL_WARNING).replace('#LIMIT#', options._maxChars) ) ) {
            return false;
          }
        }
        
        if ( this.isShowSelected != true ) {
          
          //gdy show selected nie jest zaznaczone

          for ( var length = this.values.length, i=0; i < length; i++ ) {
            /*nowe*/
            if ( options._returnCollumn == 'Y' ) {
              if ( this.values[i].r.toUpperCase().searchLike( this.searchString ) > -1 || this.values[i].d.toUpperCase().searchLike( this.searchString ) > -1 ) {
                this.values[i].checked = status;
              }
            }
              
            else {
              if ( this.values[i].d.toUpperCase().searchLike( this.searchString ) > -1 ) {
                this.values[i].checked = status;
              }
            }
          }
          
          resultArrayRender = this.find( this.searchString );
          
        }
        else {
          for ( var length = this.values.length, i=0; i < length; i++ ) {
            if ( options._returnCollumn == 'Y' ) {
              if ( this.values[i].r.toUpperCase().searchLike( this.searchString ) > -1 || this.values[i].d.toUpperCase().searchLike( this.searchString ) > -1 ) {
                if ( this.values[i].checked == true ) {
                  this.values[i].checked = status;
                }
              }
            }
              
            else {
              if ( this.values[i].d.toUpperCase().searchLike( this.searchString ) > -1 ) {
                if ( this.values[i].checked == true ) {
                  this.values[i].checked = status;
                }
              }
            }
          }
            
          if ( this.selected > 0 ) {
            this.handlers.inputSearch.val( null );
            this.searchString = '';
            this.handlers.checkboxSelectAll.prop('checked', true);
            resultArrayRender = $.makeArray( this.getChecked() );
          }
          else {
            resultArrayRender = this.values;
          }
           
        }
        
      }
      else if (this.isShowSelected) {
        var currentlySelected = this.getChecked();
        
        for (var i=0, length = currentlySelected.length; i < length; i++ ) {
          currentlySelected[i].checked = status;
        }
        
        this.handlers.checkboxSelectAll.prop('checked', status);
        resultArrayRender = this.values;
      }
      else {
        destSelectedLength = this.getArrayLength(this.values);
        

        if ( status && destSelectedLength > options._maxChars ) {
          if ( !confirm( (translations.PAELI_SELECT_ALL_WARNING).replace('#LIMIT#', options._maxChars) ) ) {
            return false;
          }
        }
        
        for ( var length = this.values.length, i=0; i < length; i++ ) {
          this.values[i].checked = status;
        }
        
        if (status)
          this.selected = this.values.length;
        else 
          this.selected = 0;
        
        
        resultArrayRender = this.values;
        
      }
      
      this.clear();
      this.showSelectedCount(true);
      this.render( resultArrayRender );
      this.showAllCount( resultArrayRender.length );
      
      return true;
    }
    
    object.getArrayLength = function(array){
      var temp = $.map(array, function(val, i){
        return val.r;  
      });

      return (temp.join(options.separator)).length;
    };

    object.showSelectedCount = function(recalculateSelected){
      
      
      if (recalculateSelected) {
        this.selected = (this.getChecked()).size();
        
      }
        
      
      this.handlers.labelShowSelected.html( translations.PAELI_POPUP_SHOW_SELECTED+' ('+this.selected+')' );
      
      if ( this.selected == 0 ) {
        this.isShowSelected = false;
        this.handlers.checkboxShowSelected.prop('checked', false);
        //this.handlers.labelShowSelected.parent().hide();
      }
      else {
        //this.handlers.labelShowSelected.parent().show();
        null;
      }
    }
    
    object.renderSelected = function(){
      var array = $.makeArray( this.getChecked() );
      this.clear();
      this.showAllCount( array.length );
      this.render( array );

      //tu sie bedzie wykluczac z clear. w clear najpierw wylaczy zaznaczenie, a ponizej linia zaznaczy
      this.handlers.checkboxSelectAll.prop('checked', true);
      
    }
    
    object.changeStatus = function( rownum, isChecked ) {
      
      object.values[rownum-1].checked = isChecked;
      
      this.calculateSelected( isChecked );
      
      if ( this.isShowSelected && this.selected == 0) {
        
        this.showSelectedCount();
        this.showAll();
        return void(0);
      } else {
        this.showSelectedCount();
      }
      
      if ( this.isShowSelected )
        this.renderSelected();
      
    }
    
    object.clear = function(){
      var self = this;
      this.resetMoreSet();
      //this.handlers.resultContainer.children().fadeOut(500, function(){
        self.handlers.resultContainer.html(null);  
        self.handlers.checkboxSelectAll.prop('checked', false);
      //});
    }
    
    object.getCheckedValues = function() {
      var arrayOfObjects = this.getChecked();
      var temp = [];
      var length = arrayOfObjects.length;
      
      for (var i = 0; i< length; i++ ) {
        temp.push( arrayOfObjects[i].r );
      }
      
      return temp;
    }
      
    
    object.getChecked = function(){
      var checkedArray = $(this.values).filter(function(index, value){
        return value.checked ? true : false;
      });
      
      return checkedArray;
    };
    
    
    
    object.showSelected = function(){
      var selectedArray = $.makeArray( this.getChecked() );
      
      if ( selectedArray.length == 0 ) {
        //alert('Nie ma zaznaczonych wartości');
        return false;
      }
      
      $('#'+native_item_id+'_select_all').prop('checked', true);
      
      this.clear();    
      this.handlers.checkboxSelectAll.prop('checked', true);
      this.showAllCount( selectedArray.length );
      this.render( selectedArray );
      return true;
    }

    
    object.showAll = function(){
      this.clear();
      this.showAllCount( this.values.length );
      this.showSelectedCount();
      this.handlers.checkboxSelectAll.prop('checked', false);
      this.render( this.values );
    }

    object.showAllCount = function( count ){
      this.handlers.labelSelectAll.html( translations.PAELI_POPUP_SELECT_ALL+' ('+count+')' );
    }
    
    object.renderAll = function(){
      this.showAllCount( count );
      this.render( this.values );
      
    };
    
    object.render = function(array){
      
      array = $.extend([], array);
      
      var arrayLength = array.length;
      var selector = $( this.handlers.resultContainer );
      this.handlers.checkboxSelectAll.prop('disabled', false);

      
      if ( arrayLength == 0 ) {
        this.handlers.checkboxSelectAll.prop('disabled', true);
        
        if (this.isShowSelected)
          selector.append( '<div class="no_data_found">'+(translations.PAELI_POPUP_NDF_SELECTED).replace('#SEARCH_STRING#', this.searchString) +'</div>' );
        else {
          var msg = (translations.PAELI_POPUP_NDF_AUTOFILTER).replace('#SEARCH_STRING#', this.searchString);
          
          selector.append( '<div class="no_data_found">'+ msg +'</div>' );
        }
        
        return void(0);
      }
      
      var array2render = array.splice(0,1000);
      var array2store = array;
      this.more2render = array2store;
      
      var template = ''
          +'{{#values}}'
          +'  <tr>'
          +'    <td width="16">'
          +'      <input {{#checked}}checked="true"{{/checked}}  type="'+( options._multiple == 'Y' ? 'checkbox' : 'radio' )+'" name="popupValues" id="'+ native_item_id +'_row_{{i}}" value="{{r}}" rownum={{i}}>'
          +'    </td>'
          +     ( options._returnCollumn == 'Y' ? '<td><label for="'+ native_item_id +'_row_{{i}}" class="return">{{r}}</label></td>' : '')
          +'    <td>'
          +'      <label for="'+ native_item_id +'_row_{{i}}">{{d}}</label>'
          +'    </td>'
          +'  </tr>'
          +'{{/values}}';
          
      result = Mustache.render(template, {"values": array2render});  
      
      if ( selector.find('table').size() > 0 ) {
        selector.find('table').append(result)
      }
      else {
        selector.append( '<table cellspacing="0" cellpadding="0">'+result+'</table>' );  
      }
      
    }
    
    
    return object;
  }

  function popupOpen(event) {
    if ( pluginObject.container == undefined )
      _set_popups();

    if (options._lov != 'Y') {
      return false;
    }
    
    _icon_loading_show();
    _icon_trigger_hide();
    
    iconPaste.popover('hide');
    
    var ajax_fn_id = options.ajaxIdentifier;
    var ajaxRequest = new htmldb_Get(null,$v('pFlowId'), 'PLUGIN='+ajax_fn_id, $v('pFlowStepId'));

    ajaxRequest.addParam('x01', 'popupLOV');
    ajaxRequest.addParam('x02', plugin.val());
      
    ajaxRequest.GetAsync(function(){
      var ajax_return = null;
      
      if (p.readyState != 4) {
        return false;
      }
      
      _icon_loading_hide();
      _icon_trigger_show();
      
      ajax_return = _parse_JSON( p.responseText );
      
      if ( ajax_return == false ) {
        return false;
      }
      
      pluginObject.data = _extendPopuplovObj( ajax_return );
      
      pluginObject.data.selectFromPlugin();      
      pluginObject.data.showAll();

      pluginObject.container.dialog('open');
      
    });
  }
  
  function finalString(string) {
    var tab = [];
    
    if ( string.length > options._maxChars ) {
      tab = string.split( separator );
      tab.pop();
      
      string = tab.join( separator );
      string = finalString( string );
    }
    else {
      return string;
    }
    
    return string;
  }    
  
  var 
    native_item_id = id,
    plugin = $('#'+id),
    mask = jQueryPAL(plugin.next('.'+selector_pluginMask+'')),
    item_container = plugin.parents('.'+selector_pluginContainer+':first'),
    //label = plugin.parents('table').find('label[for='+id+']');
    //label = label.size() == 0 ? $('[for='+id+']') : label;
    label = $('[for='+id+']'),
    label_text = label.children() > 0 ? label.children().last().text() : label.text(),
    iconTrigger = plugin.nextAll('.icons').find('.'+selector_iconTrigger),
    iconLoading = plugin.nextAll('.icons').find('.'+selector_iconLoader),
    iconPaste = jQueryPAL(plugin.nextAll('.icons').find('.'+selector_iconPasted)),

    pluginObject = {
      popup: {
        container: null,
        data: null
      }
    },
    options = $.extend(
      {
        dependingOnSelector : null,
        optimizeRefresh : true,
        pageItemsToSubmit : null,
        optionAttributes : null
      }, 
      p_optionsIn
    ),    
    translations = $.extend(options._translation_ITEM, options._translation_DICT),
    dialogConfig = null,
    apexDebugSpace = 0,
    separator = options._separator;

    

  apex.widget.initPageItem(
    plugin.attr('id'), 
    {
      /*
      nullValue : function(){
        
      },
      */
      afterModify: function(){
        null;
      },
      hide: function(){
        item_container.hide();
        label.hide();
      },
      show:function(){
        item_container.show();
        label.show();
      },
      enable:function(){
        mask.attr('disabled', false);
        _icon_trigger_show();
      },
      disable:function(){
        mask.attr('disabled', true);
        plugin.attr('disabled', true);
        
        _icon_trigger_hide();
        _icon_paste_hide();
        _icon_loading_hide();
        _cleanPlugin();
        
      },
      setValue:function(value){
        _mask_reset_data();
        _plugin_set_value( value );        
        _set_mask();
      }
      
    }
  );
  
  if ( options.dependingOnSelector) {
    $(options.dependingOnSelector).change(force_refresh_parent)
  }
  
  iconTrigger.bind('click', popupOpen);
  
  plugin.bind(
    'apexrefresh', force_refresh_parent
  ).bind(
    'change', _e_real_event_change
  ).bind(
    'getAllMask', getAllMask
  ).data({
    'options': options
  });

  mask.bind(
    'keyup', debounce(_e_mask_kayup, options._debounce_ms)
  ).bind(
    'keydown', _e_mask_kaydown
  ).bind(
    'change', _e_mask_change
  ).bind(
    'keypress', _e_mask_keypress
  ).bind(
    'removePrompt', _e_mask_removePrompt
  ).bind('setValueFromPrompt', function(e,data){
      _mask_set_value(data.display_value);
      _plugin_set_value(data.return_value);
      //_e_real_event_change(true);
      _e_mask_removePrompt();
      mask.focus();
      plugin.trigger('change', [true]);
    }
  );
  
  _mask_reset_data();  
  _setPopover();
  _set_paste();
  
  
  $(document).ready(function(){ 
    //gdy nie ma popup
    //gdy nie ma autofiltru
    //ale jest paste
    if ( options._lov == 'N' && options._autofilter == 'N' && options._allowPaste == 'Y' ) {
      var array = plugin.val().split( options._separator);

      if ( array.length > 1 ) {
        _mask_set_value( array[1] );
        _mask_set_data( {'pasted_values': array } );
        _icon_paste_show();

      }
    }

    if ( (options._autofilter == 'Y' || options._lov == 'Y') && options._lov_sql_exists == 'Y' ) {
      _set_mask();
    }
  });
}