-- Q Challenge Auth
--
-- Expects QAuthUser and QAuthMD5Hash in the config table.
-- Example:
-- config = {
--     ...
--     QAuth = {
--         type = ['md5', 'sha1'],
--         user = 'Qnet user',
--         hash = 'md5/sha1 hash of password',
--     },
--     ...
-- }

local nixio = require'nixio'
local crypto = nixio.crypto

--[[
    * challenge = "3afabede5c2859fd821e315f889d9a6c"
    * lowercase_username = "{fishking}"
    * truncated_password = "iLOVEfish1"
    * password_hash = SHA-1("<truncated password>")
    * password_hash = SHA-1("iLOVEfish1")
    * password_hash = "15ccbbd456d321ef98fa1b58e724828619b6066e"
    * key = SHA-1("<lowercase username>:<password hash>")
    * key = SHA-1("{fishking}:15ccbbd456d321ef98fa1b58e724828619b6066e")
    * key = "c05587aeb231e8f90a2df8bc66142c2a8b1be908"
    * response = HMAC-SHA-1("<challenge>"){"<key>"}
    * response = HMAC-SHA-1("3afabede5c2859fd821e315f889d9a6c"){"c05587aeb231e8f90a2df8bc66142c2a8b1be908"}
    * response = "e683c83fd16a03b6d690ea231b4f346c32ae0aaa"
    * /msg Q@CServe.quakenet.org CHALLENGEAUTH [fishking] e683c83fd16a03b6d690ea231b4f346c32ae0aaa HMAC-SHA-1
--]]

local Q = 'Q!TheQBot@CServe.quakenet.org'

return {
	['001'] = {
		function(self, source)
			if(source.mask:match('%.quakenet%.org')) then
				self:Privmsg('Q@CServe.quakenet.org', 'CHALLENGE')
			end
		end
	},

	NOTICE = {
		['CHALLENGE (%S+)'] = function(self, source, destination, challenge)
			if(source.mask == Q) then
				local config = self.config.QAuth
				local type = config.type
				local user = config.user
				local passHash = config.hash
				local hmac

				local key = crypto.hash(type):update(string.format('%s:%s', user:lower(), passHash)):final()

				if(type == 'md5') then
					hmac = 'HMAC-MD5'
				else
					hmac = 'HMAC-SHA-1'
				end

				self:Privmsg('Q@CServe.quakenet.org', 'CHALLENGEAUTH %s %s %s', user, crypto.hmac(type, key):update(challenge):final(), hmac)
			end
		end,

		['You are now logged in as %S+%.'] = function(self, source, destination)
			if(source.mask == Q and self.config.QAuth.hideHost) then
				self:Mode(self.config.nick, 'x')
			end
		end,
	}
}
