function touchHandler(event) {
	var touch = event.changedTouches[0];
	var simulatedEvent = document.createEvent("MouseEvent");
	simulatedEvent.initMouseEvent({
		touchstart: "mousedown",
		touchmove: "mousemove",
		touchend: "mouseup"
	}[event.type], true, true, window, 1,
		touch.screenX, touch.screenY,
		touch.clientX, touch.clientY, false,
		false, false, false, 0, null);
	touch.target.dispatchEvent(simulatedEvent);
	event.preventDefault();
}

function draggableOnTouchScreen(element_id) {
	var element = document.getElementById(element_id);
	if (element) {
		element.addEventListener("touchstart", touchHandler, true);
		element.addEventListener("touchmove", touchHandler, true);
		element.addEventListener("touchend", touchHandler, true);
		element.addEventListener("touchcancel", touchHandler, true);
	}
}

function createCalendarFor(element_id) {
	var datepickerOptions ={ 
	  dateFormat: 				'yy-mm-dd',
	  showOn: 						'button',
	  buttonImage: 				'/images/calendar.png', 
	  buttonImageOnly: 		true,
	  showButtonPanel: 		true, 
	  showWeek: 					true, 
	  showOtherMonths: 		true,
	  changeMonth: 				true, 
	  changeYear: 				true, 
	  selectOtherMonths: 	true,
	  beforeShow: 				beforeShowDatePicker
	};
	$(element_id).addClass('date').datepicker(datepickerOptions)
}
