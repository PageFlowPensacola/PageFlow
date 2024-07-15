<script type=module src="$$static||utils.js$$"></script>

# Please log in

$$msg|| This page requires authentication$$



<form method='POST' id=loginform>
	<label>Email: <input type='text' name='email' placeholder='Email' autocomplete=email></label>
	<label>Password: <input type='password' name='password' placeholder='Password' autocomplete='current-password'></label>
	<input type='submit' value='Login'>
	<input type=hidden name=grant_type value=session>
</form>
