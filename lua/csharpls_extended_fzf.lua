local csharpls_extend = require("csharpls_extended")
local fzf = require("fzf-lua")

local M = {
    title = "csharpls definition"
};


--- @param locations lsp.Location[] | lsp.LocationLink[]
--- @param offset_encoding string
--- @param opts any
M.fzf_handle_location = function(locations, offset_encoding, opts)
    local fetched = csharpls_extend.get_metadata(locations, offset_encoding)
    opts = opts or {}

    if vim.tbl_isempty(fetched) then
        vim.notify("No locations found")
        return
    end

    if #locations == 1 then
        vim.lsp.util.show_document(fetched[1], offset_encoding, { focus = true })
        return
    end

    -- Helper function to find a metadata location object given "<filename>@<line number>"
    -- Is there a better way to pass a location into fzf_exec? So the action can just pull the
    -- required metadata directly from the selection?
    local getLocationFromString = function(stringLocation)
        local splits = vim.split(stringLocation, "@")
        local path = splits[1]
        local lineNum = splits[2]
        local location = nil
        for _, loc in pairs(fetched) do
            if loc.filename == path and loc.lnum == tonumber(lineNum) then
                location = loc
                break
            end
        end
        return location
    end

    -- Custom previewer that uses csharpls_extended api to generate a buffer for the
    -- preview window
    local builtin = require("fzf-lua.previewer.builtin")
    local CSharpLSExPreviewer = builtin.base:extend()

    function CSharpLSExPreviewer:new(o, popts, fzf_win)
        CSharpLSExPreviewer.super.new(self, o, popts, fzf_win)
        setmetatable(self, CSharpLSExPreviewer)
        return self
    end

    function CSharpLSExPreviewer:populate_preview_buf(entry_str)
        local location = getLocationFromString(entry_str)
        if (location ~= nil) then
            local tmpbuf = self:get_tmp_buffer()
            csharpls_extend.gen_virtual_file(location.filename, tmpbuf)
            self:set_preview_buf(tmpbuf)
            self.win:update_preview_scrollbar()
            -- vim.print(self.win.preview_winid)
            -- vim.print(location)

            vim.api.nvim_win_set_cursor(self.win.preview_winid, { location.lnum, location.col })
        else
            vim.print("csharpls_extended: ERROR: location is nil")
        end
    end

    -- Disable line numbering and word wrap
    function CSharpLSExPreviewer:gen_winopts()
        local new_winopts = {
            wrap   = true,
            number = true
        }
        return vim.tbl_extend("force", self.winopts, new_winopts)
    end

    fzf.fzf_exec(function(cb)
        for _, loc in pairs(fetched) do
            cb(loc.filename .. "@" .. loc.lnum)
        end
        cb()
    end, {
        prompt = "csharpls: ",
        actions = {
            ["default"] = function(arg, _)
                local location = getLocationFromString(arg[1])
                if location ~= nil then
                    vim.lsp.util.show_document(location, offset_encoding, { focus = true })
                else
                    vim.print("csharpls_extended: ERROR: location not found in results: ")
                    -- vim.print(arg)
                    -- vim.print(fetched)
                end
            end
        },
        previewer = CSharpLSExPreviewer,
    })
end

M.fzf_handle = function(_, result, ctx, _, opts)
    -- vim.print("csharpls_handle")
    -- fixes error for "jump_to_location must be called with valid offset
    -- encoding"
    -- https://github.com/neovim/neovim/issues/14090#issuecomment-1012005684
    local offset_encoding = vim.lsp.get_client_by_id(ctx.client_id).offset_encoding
    local locations = csharpls_extend.textdocument_definition_to_locations(result)
    M.fzf_handle_location(locations, offset_encoding, opts)
end

M.fzf = function(opts)
    -- vim.print("csharpls_fzf")
    local client = csharpls_extend.get_csharpls_client()
    if client then
        -- vim.print("csharpls_fzf has client")
        local params = vim.lsp.util.make_position_params(0, 'utf-8')
        -- vim.print("csharpls_fzf params: " .. tostring(params))
        local handler = function(err, result, ctx, config)
            -- vim.print("csharpls_handler")
            ctx.params = params
            -- vim.print(params)
            M.fzf_handle(err, result, ctx, config, opts)
        end
        client:request("textDocument/definition", params, handler, 0)
    else
        vim.print("csharpls_extended: ERROR: Client not found")
    end
end

return M
