local M = {}
local Config = require('smart_cr.config')
local Parser = require('smart_cr.parser')
local Utils = require('smart_cr.utils')
local Debug = require('smart_cr.debug')

-- endwise rules for current buffer's filetype
---@type EndwiseRules
local endwise_rules = {}

---@class EndwordLists
---@field [string] EndwordList[] filetype is used for key

---@alias EndwordList table<string, string> = table<filetype, endword>

---@type EndwordLists
local endword_lists = {}

-- update rules
M.update_endwise_rules = function ()
	endwise_rules = Config.get().endwise_cr.rules
	for ft, T in pairs(endwise_rules) do
		endword_lists[ft] = {}
		for _, rule in ipairs(T) do
			local node_names = rule[3]
			local endword = rule[2]
			for _, node_name in ipairs(node_names) do
				endword_lists[ft][node_name] = endword
			end
		end
	end
end

-- check whether line contents is matched with this pattern
---@param line string line contents
---@param pattern string regex pattern
local function is_matched(line, pattern)
	return line:match(pattern) ~= nil
end

-- check this line is possible to add endwise
---@param line string
---@param rule rule
---@param endwordlist EndwordList
---@return string? endword
local function is_valid(line, rule, endwordlist)

	-- check current line regex is endwise candidate
	if not is_matched(line, rule.pattern) then
		return nil
	end

	-- check current line has endwise already
	local node = Parser.is_node(rule.ts_nodes)
	if not node then
		Debug.debug_print('not node')
		return nil
	end

	local endword = Parser.is_endwised(node, endwordlist)
	if not endword then
		Debug.debug_print('already endwised')
		return nil
	end

	return endword
end

-- <CR> with endwise
---@param mode string '<CR>|o'
---@return boolean Whether this function is executed
M.endwise_cr = function(mode)
	mode = mode or '<CR>'

	-- check enabled
	if not Config.get().endwise_cr.enabled then
		-- vim.print('not enabled')
		return false
	end

	-- don't apply endwise if no rules for filetype
	local rules = endwise_rules[vim.bo.filetype]
	if not rules then
		-- vim.print('no rules')
		return false
	end
	local endwordlist = endword_lists[vim.bo.filetype]

	-- update parser, if treesitter is not existed in this language
	local parser = vim.treesitter.get_parser()
	if not parser then
		return false
	end
	parser:parse()

	-- check endwise pattern
	---@class rule
	---@field pattern string
	---@field endword string
	---@field ts_nodes string[]
	local rule = {}
	local ctx = Utils.get_cursorinfo()
	for _, r in ipairs(rules) do
		rule.pattern, rule.endword, rule.ts_nodes = unpack(r)
		endwordlist['currentnode'] = rule.endword -- add current node's endword
		endwordlist['ERROR'] = rule.endword

		if is_valid(ctx.line, rule, endwordlist) then
			-- add endword
			if mode == '<CR>' then
				vim.api.nvim_buf_set_lines(0, ctx.lnum-1, ctx.lnum, false, {
					ctx.before,
					ctx.cur_indent,
					ctx.prev_indent .. rule.endword .. ctx.after,
				})
				vim.api.nvim_win_set_cursor(0, {ctx.lnum+1, ctx.cur_indent_count+1})
			elseif mode == 'o' then
				vim.api.nvim_buf_set_lines(0, ctx.lnum, ctx.lnum, false, {
					ctx.cur_indent,
					ctx.prev_indent .. rule.endword,
				})
				vim.api.nvim_win_set_cursor(0, {ctx.lnum+1, ctx.cur_indent_count+1})
				vim.cmd('startinsert!')
			end
			return true
		end
	end

	return false
end


M.get_rules = function(target)
	if target == 'endwise_rules' then
		return endwise_rules
	elseif target == 'endword_lists' then
		return endword_lists
	end
end



return M
