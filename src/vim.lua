local math = require('math')
local editing = textadept.editing

MODE_COMMAND = {
  keys_mode = 'command_mode',
  status = 'COMMAND MODE',
  on_enter = function()
    -- Change the caret style only in GUI mode, because with curses it just fucks up its display...
    if not CURSES then
      buffer.caret_style = buffer.CARETSTYLE_BLOCK
    end
  end
}

MODE_INSERT = {
  status = 'INSERT MODE',
  on_enter = function()
    if not CURSES then
      buffer.caret_style = buffer.CARETSTYLE_LINE
    end
  end
}

MODE_VISUAL = {
  keys_mode = 'visual_mode',
  status = 'VISUAL MODE',
  on_enter = function(self)
    if not CURSES then
      buffer.caret_style = buffer.CARETSTYLE_BLOCK
    end
    self.pos = buffer.current_pos
  end
}

MODE_EX = {
  keys_mode = 'ex_mode',
  status = 'EX MODE',
  on_enter = function()
    if not CURSES then
      buffer.caret_style = buffer.CARETSTYLE_LINE
    end
    ui.command_entry.enter_mode('ex_mode')
  end
}

function enter_mode(mode)
  keys.MODE = mode.keys_mode
  ui.statusbar_text = mode.status
  local on_enter = mode.on_enter
  if type(on_enter) == 'function' then
    on_enter(mode)
  end
end

function cmd(command)
  return {
    then_insert = function()
      command()
      enter_mode(MODE_INSERT)
    end,
    then_command = function()
      command()
      enter_mode(MODE_COMMAND)
    end
  }
end

-- Quickmarks

--[[
  TODO:
    - handle multiple buffers...
]]
local Quickmarks = {}
Quickmarks.mt = {
  __index = function(quickmarks, key)
    return function()
      local mark = quickmarks.assigned[key]
      if mark ~= nil then
        local buffer_index = mark[1]
        local pos = mark[2]
        local buf = _BUFFERS[buffer_index]

        ui.print(buffer_index)

        if buf == nil then
          ui.statusbar_text = 'quickmark ' .. tostring(key) .. ' is a dead buffer'
          return
        end

        view:goto_buffer(buffer_index)

        buffer.goto_pos(pos)
      else
        ui.statusbar_text = 'quickmark ' .. tostring(key) .. ' does not exist'
      end
    end
  end
}

function Quickmarks.new()
  local marks = {}
  local q = {
    assigned = marks,

    assign_keymap = function(self)
      local t = {}
      setmetatable(t, {
        __index = function(table, key)
          return function(self)
            marks[key] = {_BUFFERS[buffer], buffer.current_pos}
          end
        end
      })
      return t
    end
  }
  setmetatable(q, Quickmarks.mt)
  return q
end

-- MODE_COMMAND mode keybindings
local quickmarks = Quickmarks.new()

keys.command_mode = {
  -- Movement keys
  ['h'] = buffer.char_left,
  ['j'] = buffer.line_down,
  ['k'] = buffer.line_up,
  ['l'] = buffer.char_right,
  ['w'] = buffer.word_part_right, -- move word forward
  ['b'] = buffer.word_part_left, -- move word backward
  ['e'] = buffer.word_right_end, -- move to the end of the word
  ['cf'] = buffer.page_down, -- scroll 1 page down
  ['cb'] = buffer.page_up, -- scroll 1 page up
  ['ce'] = buffer.line_scroll_down,
  ['cy'] = buffer.line_scroll_up,
  ['G'] = buffer.document_end,
  ['I'] = cmd(buffer.vc_home).then_insert, -- scroll to the end
  ['$'] = buffer.line_end,
  ['^'] = buffer.home,
  ['0'] = buffer.home,
  ['A'] = cmd(buffer.line_end).then_insert,
  ['a'] = cmd(buffer.char_right).then_insert,
  ['M'] = buffer.vertical_center_caret,
  -- Quickmarks
  ['\''] = quickmarks,
  ['m'] = quickmarks:assign_keymap(),
  ['H'] = function()
    buffer.goto_pos(buffer.position_from_line(buffer.first_visible_line + 1))
  end,
  ['M'] = function()
    local middle_line = math.floor(buffer.first_visible_line + (buffer.lines_on_screen / 2))
    buffer.goto_pos(buffer.position_from_line(middle_line))
  end,
  ['L'] = function()
    buffer.goto_line(buffer.first_visible_line + buffer.lines_on_screen - 2)
  end,
  -- Editing keys
  ['o'] = cmd(function()
                buffer.line_end()
                buffer.new_line()
              end).then_insert,
  ['O'] = cmd(function()
                buffer.home()
                buffer.new_line()
                buffer.line_up()
              end).then_insert,
  ['x'] = function()
    --buffer.delete_range(buffer.current_pos, 1)
    buffer.set_selection(buffer.current_pos, buffer.current_pos + 1)
    buffer.cut()
  end, -- delete char under caret
  ['d'] = {
    ['d'] = buffer.line_cut, -- delete line under caret
    ['w'] = buffer.del_word_right, -- delete word after caret
    ['b'] = buffer.del_word_left, -- delete word before caret
    ['$'] = buffer.del_line_right, -- delete whole line after caret
    ['^'] = buffer.del_line_left, -- delete whole line before caret
    -- ['j'] = -- delete the current line and the next one
    -- ['k'] = -- delete the current line and the previous one
    ['i'] = {
      ['w'] = function()
        editing.select_word()
        buffer.cut()
      end
    }
  },
  ['D'] = buffer.del_line_right, -- delete rest of line
  ['C'] = cmd(buffer.del_line_right).then_insert, -- delete rest of line and go to insert mode.
  ['c'] = {
    ['w'] = cmd(buffer.del_word_right).then_insert,
    ['b'] = cmd(buffer.del_word_left).then_insert,
  },
  -- Buffers navigation
  ['g'] = {
    ['g'] =  buffer.document_start, -- scroll to the beginning, this and the following bindings have to be grouped
    ['t'] = function() view:goto_buffer(1, true) end,
    ['T'] = function() view:goto_buffer(-1, true) end,
  },
  -- Clipboard
  ['u'] = buffer.undo,
  ['cr'] = buffer.redo,
  -- Folds
  ['z'] = {
    -- TODO: Iterate all lines and close chidlren if fold is toplevel.
    ['M'] = {buffer.fold_all, buffer.FOLDACTION_CONTRACT}, -- close all folds
    ['m'] = function()
      local current_line = buffer.line_from_position(buffer.current_pos)
      buffer.fold_children(current_line, buffer.FOLDACTION_CONTRACT)
    end, -- fold all children
    ['o'] = function()
      local current_line = buffer.line_from_position(buffer.current_pos)
      -- ui.print('current_pos: ', buffer.current_pos, ' current_line: ', current_line)
      buffer.fold_line(current_line, buffer.FOLDACTION_EXPAND)
    end, -- unfold current line
    ['c'] = function()
      local current_line = buffer.line_from_position(buffer.current_pos)
      buffer.fold_line(current_line, buffer.FOLDACTION_CONTRACT)
    end, -- fold current line
    -- ['A'] = -- Open all folds
  },
  -- View navigation
  ['cw'] = {
    ['w'] = {ui.goto_view, 1, true}, -- next view
    ['cw'] = {ui.goto_view, -1, true},
    ['s'] = {view.split, view}, -- horizontal split
    ['v'] = {view.split, view, true}, -- vertical split
    ['c'] = {view.unsplit, view}, -- close / unsplit
  },
  [':'] = {enter_mode, MODE_EX},
  ['i'] = {enter_mode, MODE_INSERT},
  ['v'] = {enter_mode, MODE_VISUAL},
  ['V'] = {enter_mode, MODE_VISUAL},
  ['y'] = {
    ['y'] = {buffer.line_copy},
    ['w'] = function()
      local pos = buffer.current_pos
      buffer.set_selection(buffer.word_end_position(pos), pos)
      buffer.copy()
      buffer.set_empty_selection(pos)
    end,
    ['b'] = function()
      local pos = buffer.current_pos
      buffer.set_selection(buffer.word_start_position(pos), pos)
      buffer.copy()
      buffer.set_empty_selection(pos)
    end,
    ['$'] = function()
      local pos = buffer.current_pos
      buffer.line_end()
      buffer.set_selection(buffer.current_pos, pos)
      buffer.copy()
      buffer.set_empty_selection(pos)
    end,
    ['^'] = function()
      local pos = buffer.current_pos
      buffer.home()
      buffer.set_selection(buffer.current_pos, pos)
      buffer.copy()
      buffer.set_empty_selection(pos)
    end,
    ['i'] = {
      ['w'] = function()
        local pos = buffer.current_pos
        editing.select_word()
        buffer.copy()
        buffer.set_empty_selection(pos)
      end
    }
  },
  ['p'] = function()
    if ui.clipboard_text:match('\n') ~= nil then
      buffer.line_down()
      buffer.home()
    else
      buffer.char_right()
    end
    --buffer.paste()
    buffer.add_text(ui.clipboard_text)
    buffer.char_left()
  end,
  ['P'] = function()
    if ui.clipboard_text:match('\n') ~= nil then
      buffer.home()
    else
      buffer.char_left()
    end
    buffer.paste()
    buffer.char_left()
  end,
  ['/'] = {ui.find.focus},
  ['J'] = {editing.join_lines},
  ['n'] = {ui.find.find_next},
  ['N'] = {ui.find.find_prev},
  ['%'] = {editing.match_brace},
  ['*'] = function()
    editing.select_word()
    ui.find.find_entry_text = buffer.get_sel_text()
    --ui.find.focus()
  end,
  ['f'] = {},
  ['F'] = {},
  ['r'] = {},
  ['R'] = function()
    if not buffer.overtype then
      buffer.edit_toggle_overtype()
    end
    enter_mode(MODE_INSERT)
  end
}

-- MODE_VISUAL mode keybindings
function exit_visual_mode()
  buffer.set_empty_selection(MODE_VISUAL.pos)
  enter_mode(MODE_COMMAND)
end

function update_selection(n)
  start = MODE_VISUAL.pos
  if type(n) ~= 'number' then n = 0 end
  if buffer.current_pos == start and n < 0 or buffer.current_pos < start then
    start = start + 1
  end
  buffer.set_selection(buffer.current_pos + n, start)
end

keys.visual_mode = {
  ['h'] = {update_selection, -1},
  ['j'] = function()
    buffer.line_down()
    update_selection()
  end,
  ['k'] = function()
    buffer.line_up()
    update_selection()
  end,
  ['l'] = {update_selection, 1},
  ['w'] = function()
    buffer.word_part_right()
    update_selection()
  end,
  ['b'] = function()
    buffer.word_part_left()
    update_selection()
  end,
  ['e'] = function()
    buffer.word_right_end()
    update_selection()
  end,
  ['cf'] = function()
    buffer.page_down()
    update_selection()
  end,
  ['cb'] = function()
    buffer.page_up()
    update_selection()
  end,
  ['G'] = function()
    buffer.document_end()
    update_selection()
  end,
  ['$'] = function()
    buffer.line_end()
    update_selection()
  end,
  ['^'] = function()
    buffer.home()
    update_selection()
  end,
  ['0'] = function()
    buffer.home()
    update_selection()
  end,
  ['g'] = {
    ['g'] =  function()
      buffer.document_start()
      update_selection()
    end
  },
  ['i'] = {
    ['w'] = function()
      editing.select_word()
    end
  },
  ['y'] = function()
    buffer.copy()
    exit_visual_mode()
  end,
  ['d'] = function()
    buffer.cut()
    exit_visual_mode()
  end,
  ['x'] = function()
    buffer.cut()
    exit_visual_mode()
  end,
  ['esc'] = exit_visual_mode,
  ['v'] = exit_visual_mode,
  ['V'] = exit_visual_mode,
  ['f'] = {},
  ['F'] = {}
}

-- MODE_COMMAND & MODE_VISUAL ['y'|'d'|'v']['i'][...] mappings
local ranges = {
  {'<', '>'}, {"'", "'"}, {'"', '"'}, {'(', ')'}, {'[', ']'}, {'{', '}'}
}

for _, r in ipairs(ranges) do
  for _, p in ipairs(r) do
    keys.command_mode['d']['i'][p] = function()
      editing.select_enclosed(r[1], r[2])
      buffer.cut()
    end
    keys.command_mode['y']['i'][p] = function()
      local pos = buffer.current_pos
      editing.select_enclosed(r[1], r[2])
      buffer.copy()
      buffer.set_empty_selection(pos)
    end
    keys.visual_mode['i'][p] = function()
      editing.select_enclosed(r[1], r[2])
    end
  end
end

-- MODE_COMMAND & MODE_VISUAL ['f']['F'] mappings

function find_char_next(c, visual)
  local text, pos = buffer.get_cur_line()
  local bol = buffer.current_pos - pos
  local f = text:find(c, pos + 2, true)
  if f ~= nil then
    buffer.goto_pos(bol + f - 1)
    if visual then
      buffer.char_right()
      update_selection()
    end
  end
end

function find_char_prev(c, visual)
  local text, pos = buffer.get_cur_line()
  local bol = buffer.current_pos - pos
  text = text:sub(0, pos - 1):reverse()
  local f = text:find(c, 0, true)
  if f ~= nil then
    buffer.goto_pos(bol + text:len() - f)
    if visual then
      buffer.char_right()
      update_selection(-1)
    end
  end
end

for n = 32, 126 do
  local c = string.char(n)
  keys.command_mode['f'][c] = {find_char_next, c}
  keys.command_mode['F'][c] = {find_char_prev, c}
  keys.command_mode['r'][c] = function()
    buffer.set_selection(buffer.current_pos, buffer.current_pos + 1)
    buffer.replace_sel(c)
  end
  keys.visual_mode['f'][c] = {find_char_next, c, true}
  keys.visual_mode['F'][c] = {find_char_prev, c, true}
end

-- MODE_EX mode keybindings

function handle_ex_command(cmd)
  if cmd == 'q' then
    quit()
  elseif cmd == 'w' then
    io.save_file()
  elseif cmd == 'wq' or cmd == 'qw' then
    io.save_file()
    quit()
  elseif cmd == 'bw' then
    io.close_buffer()
  elseif cmd == 'e' then
    io.open_file()
  else
    -- FIXME: MODE_COMMAND#on_enter changes the statusbar text right away so this is not visible.
    ui.statusbar_text = 'unknown ex command \'' .. cmd .. '\''
  end
end

keys.ex_mode = {
  ['cc'] = cmd(ui.command_entry.finish_mode).then_command,
  ['\n'] = function()
    ui.command_entry.finish_mode(handle_ex_command)
    enter_mode(MODE_COMMAND)
  end,
  ['esc'] = function()
    ui.command_entry.finish_mode()
    enter_mode(MODE_COMMAND)
  end
}

-- Exit insert mode

function exit_insert_mode()
  if buffer.overtype then
    buffer.edit_toggle_overtype()
  end
  buffer.auto_c_cancel()
  enter_mode(MODE_COMMAND)
end

keys['cc'] = {exit_insert_mode}
keys['esc'] = {exit_insert_mode}

-- Enter command mode by default.

events.connect(events.BUFFER_NEW, function()
  enter_mode(MODE_COMMAND)
end)

events.connect(events.VIEW_NEW, function()
  enter_mode(MODE_COMMAND)
end)
