package.path = table.concat({
    'libs/?.lua',
    'libs/?/init.lua',

    '',
}, ';') .. package.path

package.cpath = table.concat({
    'libs/?.so',

    '',
}, ';') .. package.cpath



TEST_TIMEOUT = 60

function assert_loop(cq, timeout)
  local ok, err, _, thd = cq:loop(timeout)
  if not ok then
    if thd then
      err = debug.traceback(thd, err)
    end
    error(err, 2)
  end
end
