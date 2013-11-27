$(document).ready(function(){
	$(".form-control").on("blur", function(){
		$(this).removeClass("error");
	});

	var params = window.location.search.substr(1).split("&");
	for(var i = 0; i < params.length; i++){
		var param = params[i].split("=");
		if(param[0] == "err") handleError(param[1]);
		if(param[0] == "msg") handleMessage(param[1]);
	}
	history.replaceState(null, document.title, window.location.pathname);
});

function handleError(err){
	if(err === "email_taken") highlightErrors(".form-signup", ["email"]);
	else if(err === "email_not_found") highlightErrors(".form-login", ["email"]);
	else if(err === "invalid_password") highlightErrors(".form-login", ["password"]);
}

function handleMessage(msg){
	var text;
	if(msg === "password_changed") text = "Your password has been changed.";
	if(msg === "settings_updated") text = "Your settings have been updated.";
	if(text) $(".container").prepend('<div class="message alert alert-success">' + text + '</div>');	
}

function validateEmail(klass, allowBlank){
	var email = $(klass + " input[name=email]").val();
	if(allowBlank && email.length === 0) return true;
	return email.match(/.+@(.+\.)+.+/);
}

function validatePhone(klass){
	var phone = $(klass + " input[name=phone]").val();
	if(phone.length > 0){
		phone = phone.replace(/\D+/g, "");
		if(phone.length !== 10) return false;
	}
	return true;
}

function validatePassword(klass, allowBlank){
	var password = $(klass + " input[name=password]").val();
	if(allowBlank && password.length === 0) return true;
	return password.length >= 6;
}

function validatePasswordConfirmation(klass){
	return $(klass + " input[name=password]").val() === $(klass + " input[name=password_confirmation]").val();
}

function highlightErrors(klass, fields){
	$(".error").removeClass("error");
	for(var i = 0; i < fields.length; i++){
		$(klass + " input[name=" + fields[i] + "]").addClass("error");
	}
	$(klass + " input[name=" + fields[0] + "]").focus();
}

function validateSignup(){
	var KLASS = ".form-signup";
	var errors = [];
	if(!validateEmail(KLASS)) errors.push("email");
	if(!validatePhone(KLASS)) errors.push("phone");
	if(!validatePassword(KLASS)) errors.push("password");
	if(!validatePasswordConfirmation(KLASS)) errors.push("password_confirmation");

	if(errors.length === 0) return true;
	highlightErrors(KLASS, errors);
	return false;
}

function validateLogin(){
	var KLASS = ".form-login";
	var errors = [];
	if(!validateEmail(KLASS)) errors.push("email");
	if(!validatePassword(KLASS)) errors.push("password");

	if(errors.length === 0) return true;
	highlightErrors(KLASS, errors);
	return false;
}

function validateEdit(){
	var KLASS = ".form-edit";
	var errors = [];
	if(!validateEmail(KLASS, true)) errors.push("email");
	if(!validatePhone(KLASS)) errors.push("phone");
	if(!validatePassword(KLASS, true)) errors.push("password");
	if(!validatePasswordConfirmation(KLASS)) errors.push("password_confirmation");

	if(errors.length === 0) return true;
	highlightErrors(KLASS, errors);
	return false;
}

function renderCode(code, timestamp){
	if(window.activeCodeTimeout){
	    clearTimeout(window.activeCodeTimeout);
	    window.activeCodeTimeout = null;
	    $(".code-alert").hide();
	}

    var pieces = timestamp.split(" ");
    var ampm = pieces[1];
    pieces = pieces[0].split(":");
    var hours = parseInt(pieces[0]);
    var minutes = parseInt(pieces[1]);
    if(ampm === "am" && hours === 12) hours = 0;
    if(ampm === "pm") hours += 12;

    var now = new Date
    var expires = new Date(now.getTime());
    if(hours < expires.getHours()) expires.setDate(expires.getDate() + 1) // if hours reset, we've rolled over
    expires.setHours(hours);
    expires.setMinutes(minutes);
    expires.setSeconds(0);
    if(expires > now){
    	console.log(expires - now);
        $(".latest-code").text(code);
        $(".latest-code-time").text(timestamp);
        $(".code-alert").show();

        window.activeCodeTimeout = setTimeout(function(){
            $(".code-alert").hide();
        }, expires - now)
    }
}

function poll(prevMessage, userId){
    $.get('/poll/' + userId, function(data){
        if(data !== ''){
            var pieces = data.split("@");
            var code = pieces[0];
            var timestamp = pieces[1];
            if(code !== prevMessage){
            	prevMessage = code;
            	renderCode(code, timestamp);
            }
        }
    });
    setTimeout(function(){
    	poll(prevMessage, userId);
    }, 4000);
}

function pollForPayment(userId){
	var nextPoll = setTimeout(function(){
		pollForPayment(userId);
	}, 1500);
	$.get('/check_payment/' + userId, function(data){
        if(data !== ''){
        	clearTimeout(nextPoll);
        	window.location = "/";
        }
    });
}