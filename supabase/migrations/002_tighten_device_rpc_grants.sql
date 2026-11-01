-- Tighten device RPC grants: browser clients use anon key only for these calls.
revoke execute on function public.validate_invite_code(text) from public, anon, authenticated;
revoke execute on function public.device_invite_codes_enabled() from authenticated;
revoke execute on function public.touch_device_seen() from authenticated;

revoke execute on function public.request_device_access(text, text, text, text) from authenticated;
