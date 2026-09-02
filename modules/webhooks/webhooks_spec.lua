package.path = table.concat({
    'libs/?.lua',
    'libs/?/init.lua',
    'spec/?.lua',
    '',
}, ';') .. package.path

package.cpath = table.concat({
    'libs/?.so',
    '',
}, ';') .. package.cpath

local busted = require 'busted'
local describe = busted.describe
local it = busted.it
local before_each = busted.before_each
local module_helper = require 'module_helper'

describe('webhooks module', function()
    local mock
    local msg_calls
    local handlers
    local parse_form_encoded

    before_each(function()
        mock = module_helper.mock_ivar2({
            config = {
                webhookSecrets = {
                    dispatcharr = "bilbao",
                    jellyfin = "jellyfin-secret",
                },
            },
        })

        msg_calls = {}
        mock.Msg = function(self, event, dest, source, message)
            table.insert(msg_calls, { event = event, dest = dest, source = source, message = message })
        end

        -- Stub webserver (module calls ivar2.webserver.regUrl on load)
        mock.webserver = { regUrl = function() end }

        -- Load the module to extract handler functions for direct testing
        local loader = assert(loadfile('modules/webhooks/init.lua'))
        local env = { ivar2 = mock, package = package }
        setmetatable(env, { __index = _G })
        setfenv(loader, env)
        local mod = loader()
        handlers = mod.handlers
        parse_form_encoded = mod.parse_form_encoded
    end)

    local function call_handler(system, json)
        msg_calls = {}
        local handler = handlers[system]
        if handler then
            local message = handler(json)
            if message then
                mock:Msg('privmsg', '#lab', nil, message)
            end
        end
        return msg_calls
    end

    describe('dispatcharr events', function()
        it('formats channel_start event', function()
            local calls = call_handler('dispatcharr', {
                channel_name = 'CNN',
                stream_name = 'HD Feed',
                stream_id = 'abc123',
                provider_name = 'IPTV Provider',
                profile_used = '720p',
            })
            assert.are_equal(1, #calls)
            assert.are_equal('#lab', calls[1].dest)
            assert.is_not_nil(calls[1].message:match('CNN'))
            assert.is_not_nil(calls[1].message:match('▶'))
            assert.is_not_nil(calls[1].message:match('HD Feed'))
            assert.is_not_nil(calls[1].message:match('IPTV Provider'))
            assert.is_not_nil(calls[1].message:match('720p'))
        end)

        it('formats channel_stop event', function()
            local calls = call_handler('dispatcharr', {
                channel_name = 'BBC News',
                runtime = 7200,
                total_bytes = 536870912,
            })
            assert.are_equal(1, #calls)
            assert.is_not_nil(calls[1].message:match('BBC News'))
            assert.is_not_nil(calls[1].message:match('stopped'))
            assert.is_not_nil(calls[1].message:match('512.0 MB'))
        end)

        it('formats channel_error event', function()
            local calls = call_handler('dispatcharr', {
                channel_name = 'Sky Sports',
                error_type = 'connection_failed',
                error_message = 'Connection timed out after 30s',
                attempts = 3,
            })
            assert.are_equal(1, #calls)
            assert.is_not_nil(calls[1].message:match('Sky Sports'))
            assert.is_not_nil(calls[1].message:match('connection_failed'))
            assert.is_not_nil(calls[1].message:match('timed out'))
        end)

        it('formats channel_reconnect event', function()
            local calls = call_handler('dispatcharr', {
                channel_name = 'Al Jazeera',
                attempt = 2,
                max_attempts = 5,
            })
            assert.are_equal(1, #calls)
            assert.is_not_nil(calls[1].message:match('Al Jazeera'))
            assert.is_not_nil(calls[1].message:match('reconnected'))
            assert.is_not_nil(calls[1].message:match('2/5'))
        end)

        it('formats channel_failover event', function()
            local calls = call_handler('dispatcharr', {
                channel_name = 'ESPN',
                reason = 'buffering_timeout',
                duration = 15,
            })
            assert.are_equal(1, #calls)
            assert.is_not_nil(calls[1].message:match('ESPN'))
            assert.is_not_nil(calls[1].message:match('failover'))
            assert.is_not_nil(calls[1].message:match('buffering_timeout'))
        end)

        it('suppresses stream_switch noise', function()
            local calls = call_handler('dispatcharr', {
                channel_name = 'CNN',
                new_url = 'http://example.com/stream/123',
                stream_id = 'xyz789',
            })
            assert.are_equal(0, #calls)
        end)

        it('formats recording_start event', function()
            local calls = call_handler('dispatcharr', {
                channel_name = 'Discovery',
                recording_id = 'rec_001',
            })
            assert.are_equal(1, #calls)
            assert.is_not_nil(calls[1].message:match('Discovery'))
            assert.is_not_nil(calls[1].message:match('recording started'))
        end)

        it('formats recording_end complete event', function()
            local calls = call_handler('dispatcharr', {
                channel_name = 'Discovery',
                recording_id = 'rec_001',
                bytes_written = 1073741824,
            })
            assert.are_equal(1, #calls)
            assert.is_not_nil(calls[1].message:match('complete'))
            assert.is_not_nil(calls[1].message:match('1.0 GB'))
        end)

        it('formats recording_end interrupted event', function()
            local calls = call_handler('dispatcharr', {
                channel_name = 'Discovery',
                recording_id = 'rec_001',
                interrupted = true,
                bytes_written = 536870912,
            })
            assert.are_equal(1, #calls)
            assert.is_not_nil(calls[1].message:match('interrupted'))
        end)

        it('suppresses epg_refresh noise', function()
            local calls = call_handler('dispatcharr', {
                source_name = 'XMLTV Guide',
                programs = 500,
                channels = 50,
            })
            assert.are_equal(0, #calls)
        end)

        it('suppresses m3u_refresh noise', function()
            local calls = call_handler('dispatcharr', {
                account_name = 'IPTV Provider',
                streams_created = 10,
                streams_updated = 5,
                streams_deleted = 2,
                total_processed = 200,
                elapsed_time = 12.34,
            })
            assert.are_equal(0, #calls)
        end)

        it('formats login_failed event', function()
            local calls = call_handler('dispatcharr', {
                user = 'admin',
                client_ip = '192.168.1.100',
                reason = 'invalid credentials',
            })
            assert.are_equal(1, #calls)
            assert.is_not_nil(calls[1].message:match('login failed'))
            assert.is_not_nil(calls[1].message:match('admin'))
            assert.is_not_nil(calls[1].message:match('192.168.1.100'))
        end)

        it('formats vod_start event', function()
            local calls = call_handler('dispatcharr', {
                content_name = 'Big Buck Bunny',
                content_uuid = 'vod-uuid-123',
                client_ip = '10.0.0.5',
                username = 'viewer1',
            })
            assert.are_equal(1, #calls)
            assert.is_not_nil(calls[1].message:match('Big Buck Bunny'))
            assert.is_not_nil(calls[1].message:match('viewer1'))
        end)

        it('handles unknown event gracefully', function()
            local calls = call_handler('dispatcharr', {
                weird_field = 'something',
                another_thing = 42,
            })
            assert.are_equal(0, #calls)
        end)

        it('handles falsy values stripped by Dispatcharr', function()
            -- Dispatcharr strips falsy values, so interrupted=False disappears
            local calls = call_handler('dispatcharr', {
                channel_name = 'Test Channel',
                recording_id = 'rec_999',
                bytes_written = 1000000,
                -- interrupted is missing (was False, got stripped)
            })
            assert.are_equal(1, #calls)
            assert.is_not_nil(calls[1].message:match('complete'))
        end)
    end)

    describe('unknown system', function()
        it('returns nil for unknown system handler', function()
            local calls = call_handler('nonexistent', { test = 'data' })
            assert.are_equal(0, #calls)
        end)
    end)

    describe('jellyfin events', function()
        it('formats PlaybackStart payload', function()
            local calls = call_handler('jellyfin', {
                NotificationType = 'PlaybackStart',
                NotificationUsername = 'lab',
                SeriesName = 'Breaking Bad',
                Name = 'Pilot',
                SeasonNumber00 = '1',
                EpisodeNumber00 = '1',
                DeviceName = 'TV',
            })
            assert.are_equal(1, #calls)
            assert.is_not_nil(calls[1].message:match('%[Jellyfin%]'))
            assert.is_not_nil(calls[1].message:match('started Breaking Bad S01E01 Pilot on TV'))
        end)

        it('suppresses payload with empty message', function()
            local calls = call_handler('jellyfin', { token = 'x', message = '' })
            assert.are_equal(0, #calls)
        end)

        it('suppresses payload with missing message', function()
            local calls = call_handler('jellyfin', { token = 'x' })
            assert.are_equal(0, #calls)
        end)

        it('has jellyfin in test webhookSecrets', function()
            -- Secret check applies to jellyfin at the router level, same as dispatcharr
            assert.are_equal('jellyfin-secret', mock.config.webhookSecrets.jellyfin)
        end)
    end)

    describe('form-encoded payloads', function()
        it('parses form-encoded channel_start correctly', function()
            local data = parse_form_encoded(
                'channel_name=CNN&stream_name=HD+Feed&stream_id=abc123&provider_name=IPTV+Provider&profile_used=720p')
            local calls = call_handler('dispatcharr', data)
            assert.are_equal(1, #calls)
            assert.is_not_nil(calls[1].message:match('CNN'))
            assert.is_not_nil(calls[1].message:match('HD Feed'))
        end)

        it('parses form-encoded recording_end with boolean', function()
            local data = parse_form_encoded(
                'channel_name=Discovery&recording_id=rec_001&interrupted=True&bytes_written=536870912')
            assert.is_true(data.interrupted)
            assert.are_equal(536870912, data.bytes_written)
            local calls = call_handler('dispatcharr', data)
            assert.are_equal(1, #calls)
            assert.is_not_nil(calls[1].message:match('interrupted'))
        end)

        it('formats client_connect with all fields', function()
            local data = {
                channel_name = 'CNN',
                client_ip = '192.168.1.50',
                client_id = 'conn_abc123',
                user_agent = 'VLC/3.0',
                username = 'alice',
            }
            local calls = call_handler('dispatcharr', data)
            assert.are_equal(1, #calls)
            assert.is_not_nil(calls[1].message:find('connected'))
            assert.is_not_nil(calls[1].message:find('192.168.1.50'))
            assert.is_not_nil(calls[1].message:find('alice'))
            assert.is_not_nil(calls[1].message:find('VLC/3.0'))
        end)

        it('formats client_connect without username or user_agent', function()
            local data = {
                channel_name = 'BBC',
                client_ip = '10.0.0.5',
                client_id = 'conn_xyz789',
            }
            local calls = call_handler('dispatcharr', data)
            assert.are_equal(1, #calls)
            assert.is_not_nil(calls[1].message:find('connected'))
            assert.is_not_nil(calls[1].message:find('10.0.0.5'))
            assert.is_nil(calls[1].message:find('%('))
        end)

        it('formats client_disconnect with all fields', function()
            local data = {
                channel_name = 'CNN',
                client_ip = '192.168.1.50',
                client_id = 'conn_abc123',
                duration = 3600,
                bytes_sent = 15728640,
                username = 'alice',
            }
            local calls = call_handler('dispatcharr', data)
            assert.are_equal(1, #calls)
            assert.is_not_nil(calls[1].message:find('disconnected'))
            assert.is_not_nil(calls[1].message:find('3600s'))
            assert.is_not_nil(calls[1].message:find('15.0 MB'))
            assert.is_not_nil(calls[1].message:find('alice'))
        end)

        it('handles client_disconnect form-encoded with numeric normalization', function()
            local data = parse_form_encoded(
                'channel_name=CNN'
                .. '&client_ip=192.168.1.50'
                .. '&client_id=conn_abc'
                .. '&duration=3600'
                .. '&bytes_sent=15728640'
                .. '&username=bob')
            assert.are.equal('CNN', data.channel_name)
            assert.are.equal('192.168.1.50', data.client_ip)
            assert.are.equal(3600, data.duration)
            assert.are.equal(15728640, data.bytes_sent)
            assert.are.equal('bob', data.username)
            local calls = call_handler('dispatcharr', data)
            assert.are_equal(1, #calls)
            assert.is_not_nil(calls[1].message:find('disconnected'))
            assert.is_not_nil(calls[1].message:find('3600s'))
            assert.is_not_nil(calls[1].message:find('bob'))
        end)

        it('handles URL-encoded values in form data', function()
            local data = parse_form_encoded(
                'channel_name=Sky%2BSports&error_type=connection_failed&error_message=Timeout%2Bafter%2B30s')
            assert.are_equal('Sky+Sports', data.channel_name)
            assert.are_equal('Timeout+after+30s', data.error_message)
        end)

        it('converts bare plus to space in form data', function()
            local data = parse_form_encoded(
                'channel_name=Sky+Sports&error_message=Timeout+after+30s')
            assert.are_equal('Sky Sports', data.channel_name)
            assert.are_equal('Timeout after 30s', data.error_message)
        end)

        it('converts empty strings to nil', function()
            local data = parse_form_encoded('channel_name=&stream_id=test')
            assert.is_nil(data.channel_name)
            assert.are_equal('test', data.stream_id)
        end)
    end)
end)
