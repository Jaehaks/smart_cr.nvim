local M = {}
local Debug = require('smart_cr.debug')

-- class definition for BFS
---@class smart_cr.bfs.queue
---@field [string] smart_cr.bfs.queue.item[]

---@class smart_cr.bfs.queue.item
---@field node TSNode
---@field depth number depth on tree
---@field parent string node name of parent


---@alias smart_cr.bfs.nodefunc fun(node:smart_cr.bfs.queue.item, endwordlist:EndwordList?, memory:table?): table?

-- do func() for all children nodes using breadth-first-search
---@param root TSNode
---@param endwordlist EndwordList? endword list of current filetype
-- -@param func fun(node:smart_cr.bfs.queue.item, endwordlist:EndwordList?, memory:table?): table?
---@param func smart_cr.bfs.nodefunc
local function for_nodes(root, endwordlist, func)

	---@type smart_cr.bfs.queue
	local queue = {{node = root, depth = 0, parent = ''}} -- start node
	local front = 1 -- bfs using index, no table.remove
	local back = 1

	local memory = {}
	while front <= back do
		-- go to next node
		local current = queue[front]
		front = front + 1

		-- Do something
		local result = func(current, endwordlist, memory)
		if result then
			return result
		end

		-- add only node, not field. (ex, class_definition(O), classdef(X) )
		for _, child in ipairs(current.node:named_children()) do
			back = back+1
			queue[back] = {node = child, depth = current.depth + 1, parent = current.node:type()}
		end
	end

	return nil
end

-- find root node
---@param snode TSNode? Start node to detect root node
---@param endwordlist string[] if it is valid, find root which is included in endwordlist
---@return TSNode? root node
local function get_root_node(snode, endwordlist)
	local at_cursor = not snode -- if snode is nil, start from current node

	-- get current node if snode is nil
	if not snode then
		snode = vim.treesitter.get_node({ignore_injections = false})
		if not snode then
			return nil
		end
	end

	-- get current cursor position
	local cursor = vim.api.nvim_win_get_cursor(0)
	cursor[1] = cursor[1] - 1

	-- check current node is worth checking,
	-- if line is not start node, don't add endwise, like comment / comment block / wrong endwise
	-- get root node at where cursor is
	---@type TSNode?
	local pnode, root = snode, snode
	while pnode do
		local start_row = pnode:range()

		if at_cursor and start_row ~= cursor[1] then
			break
		end

		if not endwordlist or endwordlist[pnode:type()] then
			root = pnode
		end
		pnode = pnode:parent()
	end

	return root
end



-- check current node under cursor is target_node
---@param targets table target node to check this region under cursor is the node
---@return TSNode? Object of treesitter tree
M.is_node = function(targets)
	table.insert(targets, 'ERROR') -- consider ERROR node automatically

	-- get root
	local root = get_root_node()
	if not root then
		return nil
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	cursor[1] = cursor[1] - 1

	-- get child belongs to {target} at cursor line
	---@type smart_cr.bfs.nodefunc
	local function get_child_node(item)
		local node = item.node
		local start_row = node:range()
		if start_row == cursor[1] and vim.tbl_contains(targets, node:type()) then
			return {node}
		end
		return nil
	end

	local node = for_nodes(root, nil, get_child_node)
	if node then
		return node[1]
	end

	return nil
end



---@param snode TSNode start node
---@param endwordlist EndwordList endword list of current filetype
---@return string? endword of snode
M.is_endwised = function(snode, endwordlist)

	-- get root node which has endwise structure from cursor region
	local root = get_root_node(snode, endwordlist)
	if not root then
		return nil
	end

	-- add 'ERROR' node to check endword
	local endword = endwordlist['currentnode']

	-- find commentmark and escaped
	local commentstring = vim.o.commentstring
	local commentmark = commentstring:gsub('%%s', ''):gsub('%s+$', ''):gsub('(.)', '%%%1')

	---@type smart_cr.bfs.nodefunc
	local function check_endword(item, ewlist, memory)
		local node = item.node

		if ewlist[node:type()] then

			-- 1) check each node has proper endword
			Debug.debug_print('-----------------------------' .. node:type() .. '--------------------')
			local endword_snode = vim.split(vim.treesitter.get_node_text(node, 0), '\n', {plain = true})
			Debug.debug_print({endword_snode[1], endword_snode[#endword_snode]})
			local has_endword = endword_snode[#endword_snode]:find('%s*' .. endword .. '%s*$') or false
			has_endword = has_endword and not endword_snode[#endword_snode]:find(commentmark .. '%s+' .. endword .. '[^%w]*$')
			if not has_endword then
				Debug.debug_print ('-----------------------------' .. node:type() .. ' not has endword')
				return {endword}
			end

			-- 2) check node's end row is duplicated
			local end_row = node:end_()
			if vim.tbl_contains(memory, end_row) then
				Debug.debug_print('----------------------------- duplicated end row')
				return {endword}
			end
			table.insert(memory, end_row)

			-- -- check
			local range = {node:range()}
			Debug.debug_print('[' .. item.depth .. '-' .. item.parent .. ']  ' .. node:type() .. ' -- ' .. range[1] .. ' ' .. range[3] .. '//' .. tostring(node:named()) .. '//' .. tostring(has_endword) )
		end

		return nil
	end

	-- check current nodes is already endwised
	local final_endword = for_nodes(root, endwordlist, check_endword)
	if final_endword then
		return final_endword[1]
	end

	return nil
end

-- check the cursor is inside of brackets
---@param ctx smart_cr.ctx
---@param bracket_pairs table<string, string> check smart_cr.config.bracket_cr
---@return boolean Whether cursor is in brackets
M.is_brackets = function(ctx, bracket_pairs)

	-- get bracket pattern to match
	local open_pattern = ''
	local close_pattern = ''
	for open, close in pairs(bracket_pairs) do
		open_pattern = open_pattern .. vim.pesc(open)
		close_pattern = close_pattern .. vim.pesc(close)
	end
	open_pattern = '([' .. open_pattern .. '])%s*$'
	close_pattern = '^%s*([' .. close_pattern .. '])'

	local before_bracket = ctx.before:match('.*' .. open_pattern) -- matched before bracket which is closed to cursor
	local after_bracket = ctx.after:match(close_pattern) -- matched after bracket which is closed to cursor

	-- Check open and closed parentheses pairs
	if before_bracket and after_bracket and after_bracket == bracket_pairs[before_bracket] then
		return true
	end

	return false
end



return M
