$(document).ready(function(){
	$(".form-control").on("blur", function(){
		$(this).removeClass("error");
	});

	var params = window.location.search.substr(1).split("&");
	for(var i = 0; i < params.length; i++){
		var param = params[i].split("=");
		if(param[0] == "err") handleError(param[1]);
	}
});

function handleError(err){
	if(err === "email_taken") highlightErrors(".form-signup", ["email"]);
	else if(err === "email_not_found") highlightErrors(".form-login", ["email"]);
	else if(err === "invalid_password") highlightErrors(".form-login", ["password"]);
}

function validateEmail(klass){
	var email = $(klass + " input[name=email]").val();
	return email.match(/.+@(.+\.)+.+/);
}

function validatePassword(klass){
	var password = $(klass + " input[name=password]").val();
	return password.length >= 6;
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

	var phone = $(KLASS + " input[name=phone]").val();
	if(phone.length > 0){
		phone = phone.replace(/\D+/g, "");
		if(phone.length < 10 || phone.length > 11) errors.push("phone");
	}

	if(!validatePassword(KLASS)) errors.push("password");

	if($(KLASS + " input[name=password]").val() !== $(KLASS + " input[name=password_confirmation]").val()) errors.push("password_confirmation");

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