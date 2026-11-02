-- Remove direct execution rights from internal parsing/validation helpers.
-- They are called by narrowly scoped SECURITY DEFINER routines, not by browser clients.
revoke execute on function private.request_device_token_hash() from public, anon, authenticated;
revoke execute on function private.validate_invite_code(text) from public, anon, authenticated;
