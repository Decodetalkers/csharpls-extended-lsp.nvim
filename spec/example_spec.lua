local csharpls = require("csharpls_extended")

local example_file_1 = "csharp:/metadata/projects/App/assemblies/System.Console/symbols/System.Console.cs"
local example_file_2 = "file://App/assemblies/System.Console/symbols/System.Console.cs"

describe('Url Check', function()
    it('is true url', function()
        local found = csharpls.is_lsp_url(example_file_1)
        assert.are_true(found)
    end)
    it('is local url', function()
        local found = csharpls.is_lsp_url(example_file_2)
        assert.are_false(found)
    end)
end)
