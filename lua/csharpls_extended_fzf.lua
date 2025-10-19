local csharpls_extend = require("csharpls_extended")

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

    vim.print(fetched)
end

M.fzf_handle = function(_, result, ctx, _, opts)
    -- fixes error for "jump_to_location must be called with valid offset
    -- encoding"
    -- https://github.com/neovim/neovim/issues/14090#issuecomment-1012005684
    local offset_encoding = vim.lsp.get_client_by_id(ctx.client_id).offset_encoding
    local locations = csharpls_extend.textdocument_definition_to_locations(result)
    M.fzf_handle_location(locations, offset_encoding, opts)
end

M.fzf = function(opts)
    local client = csharpls_extend.get_csharpls_client()
    if client then
        local params
        params = vim.lsp.util.make_position_params(0, 'utf-8')
        local handler = function(err, result, ctx, config)
            ctx.params = params
            M.fzf_handle(err, result, ctx, config, opts)
        end
        client:request("textDocument/definition", params, handler, 0)
    end
end

return M
