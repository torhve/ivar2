local zlib = require 'zlib'

-- Mock state (reset in before_each)
local mock_response = {}
local client_calls = {}

local function reset_mock()
	mock_response = {
		status = '200',
		headers = {},
		body = '',
		error = nil,
		throw_error = nil,
		stream_nil = false,
		connection_version = 1.1,
	}

	client_calls = {
		upsert = {},
		set_body = nil,
		client_version = nil,
		client_timeout = nil,
		go_timeout = nil,
	}
end

-- Save originals for teardown
local real_http_request = package.loaded['http.request']
local real_simplehttp = package.loaded['simplehttp']

-- Clear cached simplehttp so our require picks up the mock
package.loaded['simplehttp'] = nil
package.loaded['http.request'] = {
	new_from_uri = function(uri_t)
		return {
			version = nil,
			timeout = nil,
			headers = {
				upsert = function(_, k, v)
					table.insert(client_calls.upsert, {k, v})
				end,
			},
			set_body = function(_, data)
				client_calls.set_body = data
			end,
			go = function(self, timeout)
				client_calls.go_timeout = timeout
				client_calls.client_version = self.version
				client_calls.client_timeout = self.timeout

				if mock_response.throw_error then
					error(mock_response.throw_error)
				end

				if mock_response.error then
					return nil, mock_response.error
				end

				local resp_headers = mock_response.headers or {}
				local keys = {}
				for k in pairs(resp_headers) do
					table.insert(keys, k)
				end

				local headers_obj = {
					get = function(_, key)
						if key == ':status' then return mock_response.status end
						return resp_headers[key]
					end,
					each = function()
						local i = 0
						return function()
							i = i + 1
							local k = keys[i]
							if k then return k, resp_headers[k] end
						end
					end,
				}

				local stream
				if not mock_response.stream_nil then
					stream = {
						get_body_chars = function(_, limit)
							return (mock_response.body or ''):sub(1, limit)
						end,
						get_body_as_string = function()
							return mock_response.body or ''
						end,
						shutdown = function() end,
						connection = {
							version = mock_response.connection_version,
						},
					}
				end

				return headers_obj, stream
			end,
		}
	end,
}

local simplehttp = require 'simplehttp'

teardown(function()
	package.loaded['http.request'] = real_http_request
	package.loaded['simplehttp'] = real_simplehttp
end)

before_each(function()
	reset_mock()
end)

describe('simplehttp', function()
	it('makes a request with a string URL', function()
		mock_response.body = 'hello'
		local data, uri, response = simplehttp('http://example.com')
		assert.are_equal('hello', data)
		assert.are_equal('http://example.com', uri)
		assert.are_equal(200, response.status_code)
	end)

	it('makes a request with a table URL', function()
		mock_response.body = 'from table'
		local data, uri = simplehttp({url = 'http://example.com/table'})
		assert.are_equal('from table', data)
		assert.are_equal('http://example.com/table', uri)
	end)

	it('strips URL fragments', function()
		mock_response.body = 'ok'
		local _, uri = simplehttp('http://example.com#section')
		assert.is_nil(uri:find('#'))
	end)

	it('trims whitespace from URL', function()
		mock_response.body = 'ok'
		local _, uri = simplehttp('  http://example.com  ')
		assert.are_equal('http://example.com', uri)
	end)

	it('sets custom headers from table URL', function()
		simplehttp({url = 'http://x', version = 1, headers = {['X-Foo'] = 'bar', Authorization = 'token'}})
		assert.are_equal(2, #client_calls.upsert)
		assert.are_equal('X-Foo', client_calls.upsert[1][1])
		assert.are_equal('bar', client_calls.upsert[1][2])
		assert.are_equal('Authorization', client_calls.upsert[2][1])
		assert.are_equal('token', client_calls.upsert[2][2])
	end)

	it('sets a custom HTTP method', function()
		simplehttp({url = 'http://x', method = 'POST'})
		assert.are_equal(':method', client_calls.upsert[1][1])
		assert.are_equal('POST', client_calls.upsert[1][2])
	end)

	it('sets a request body', function()
		simplehttp({url = 'http://x', data = 'payload'})
		assert.are_equal('payload', client_calls.set_body)
	end)

	it('respects custom timeout from table URL', function()
		simplehttp({url = 'http://x', timeout = 3000})
		assert.are_equal(3000, client_calls.client_timeout)
		assert.are_equal(3000, client_calls.go_timeout)
	end)

	it('overrides client HTTP version', function()
		simplehttp({url = 'http://x', version = 2})
		assert.are_equal(2, client_calls.client_version)
	end)

	it('passes response headers through', function()
		mock_response.headers = {['content-type'] = 'text/plain'}
		local _, _, response = simplehttp('http://x')
		assert.are_equal('text/plain', response.headers['content-type'])
	end)

	it('calls the callback with data, uri, and response', function()
		mock_response.body = 'cb data'
		local cb_data, cb_uri, cb_resp
		local ret_data, ret_uri, ret_resp = simplehttp('http://cb.example', function(d, u, r)
			cb_data = d
			cb_uri = u
			cb_resp = r
		end)
		assert.are_equal('cb data', cb_data)
		assert.are_equal('http://cb.example', cb_uri)
		assert.are_equal(200, cb_resp.status_code)
		assert.are_equal(cb_data, ret_data)
		assert.are_equal(cb_uri, ret_uri)
	end)

	it('returns data, uri, and response when no callback', function()
		mock_response.body = 'ret val'
		local data, uri, response = simplehttp('http://ret.example')
		assert.are_equal('ret val', data)
		assert.are_equal('http://ret.example', uri)
		assert.are_equal(200, response.status_code)
	end)

	it('truncates body with limit parameter', function()
		mock_response.body = 'hello world'
		local data = simplehttp('http://x', nil, nil, 5)
		assert.are_equal('hello', data)
	end)

	it('returns nil and error on request failure', function()
		mock_response.error = 'connection refused'
		local data, err = simplehttp('http://x')
		assert.is_nil(data)
		assert.are_equal('connection refused', err)
	end)

	it('decompresses gzip-encoded bodies', function()
		local original = 'hello world'
		local deflate = zlib.deflate()
		local compressed = deflate(original)
		local tail = deflate(nil) or ''
		compressed = compressed .. tail

		mock_response.body = compressed
		mock_response.headers['content-encoding'] = 'gzip'

		local data = simplehttp('http://x')
		assert.are_equal(original, data)
	end)

	it('includes the response status code as a number', function()
		local _, _, response = simplehttp('http://x')
		assert.is_number(response.status_code)
		assert.are_equal(200, response.status_code)
	end)

	it('includes the connection version in the response', function()
		mock_response.connection_version = 2
		local _, _, response = simplehttp('http://x')
		assert.are_equal(2, response.version)
	end)

	it('handles nil stream without crashing (HEAD/204/304)', function()
		mock_response.stream_nil = true
		mock_response.status = '204'
		mock_response.headers = {['content-type'] = 'text/plain'}
		local _, _, response = simplehttp('http://x')
		assert.are_equal(204, response.status_code)
		assert.is_nil(response.version)
		assert.are_equal('text/plain', response.headers['content-type'])
	end)

	it('handles exceptions during request', function()
		mock_response.throw_error = 'Broken pipe'
		local data, err = simplehttp('http://x')
		assert.is_nil(data)
		assert.truthy(err:match('Broken pipe'))
	end)
end)
