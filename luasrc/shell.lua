local dir = require 'pl.dir'
local func = require 'pl.func'
local path = require 'pl.path'
local stringx = require 'pl.stringx'
local textx = require 'pl.text'

local function convertExtension(extension, newExtension, filePath)
    if not stringx.endswith(filePath, "." .. extension)  then
        error("Expected ." .. extension .. " file")
    end
    return path.basename(filePath):sub(1, -string.len(extension) - 1) .. newExtension
end
local function luaToMd(luaFile)
    return convertExtension("lua", "md", luaFile)
end
local function mdToHTML(mdFile)
    return convertExtension("md", "html", mdFile)
end

local function makeSectionTOC(packageName, sectionPath)
    local sectionName = path.splitext(path.basename(sectionPath))
    local sectionHTML = dokx._readFile(sectionPath)
    local output = [[<li><a href="#]] .. packageName .. "." .. sectionName .. ".dok" .. [[">]] .. sectionName .. "</a>\n" .. sectionHTML .. "</li>\n"
    return output
end

local function makeAnchorName(packageName, sectionName)
    return packageName .. "." .. sectionName .. ".dok"
end

local function makeSectionHTML(packageName, sectionPath)
    local basename = path.basename(sectionPath)
    local sectionName = path.splitext(basename)
    local sectionHTML = dokx._readFile(sectionPath)
    local output = [[<div class='docSection'>]]
    output = output .. [[<a name="]] .. makeAnchorName(packageName, sectionName) .. [["></a>]]
    output = output .. sectionHTML
    output = output .. [[</div>]]
    return output
end

local function prependPath(prefix)
    return function(suffix)
        return path.join(prefix, suffix)
    end
end

local function indexEntry(package)
    return "<li><a href=\"" .. package .. "/index.html\">" .. package .. "</a></li>"
end

function dokx.combineHTML(tocPath, input, config)
    dokx.logger:info("Generating package documentation index for " .. input)

    local outputName = "index.html"

    if not path.isdir(input) then
        error("Not a directory: " .. input)
    end

    local extraDir = path.join(input, "extra")
    local extraSections = {}
    if path.isdir(extraDir) then
        extraSections = dir.getfiles(extraDir, "*.html")
    end

    local outputPath = path.join(input, outputName)
    local sectionPaths = dir.getfiles(input, "*.html")
    local packageName = dokx._getLastDirName(input)

    sectionPaths = tablex.filter(sectionPaths, function(x)
        if stringx.endswith(x, 'init.html') then
            table.insert(extraSections, 1, path.join(input, 'init.html'))
            return false
        end
        return true
    end)

    local sortedExtra = tablex.sortv(extraSections)
    local sorted = tablex.sortv(sectionPaths)

    local content = ""

    for _, sectionPath in sortedExtra do
        dokx.logger:info("Adding " .. sectionPath .. " to index")
        content = content .. makeSectionHTML(packageName, sectionPath)
    end

    for _, sectionPath in sorted do
        dokx.logger:info("Adding " .. sectionPath .. " to index")
        content = content .. makeSectionHTML(packageName, sectionPath)
    end

    -- Add the generated table of contents from the given file, if provided
    local toc = ""
    if tocPath and tocPath ~= "none" then
        toc = dokx._readFile(tocPath)
    end

    local templateHTML = dokx._readFile("templates/package.html")
    local template = textx.Template(templateHTML)

    local mathjax = ""
    if not config or config.mathematics then
        mathjax = dokx._readFile("templates/mathjax.html")
    end
    local templateHTML = dokx._readFile("templates/package.html")

    local output = template:safe_substitute {
        packageName = packageName,
        toc = toc,
        content = content,
        scripts = mathjax
    }

    dokx.logger:info("Writing to " .. outputPath)

    local outputFile = io.open(outputPath, 'w')
    outputFile:write(output)
    outputFile:close()
end

function dokx.generateHTML(output, inputs)
    if not path.isdir(output) then
        dokx.logger:info("Directory " .. output .. " not found; creating it.")
        path.mkdir(output)
    end

    local function handleFile(markdownFile, outputPath)
        local sundown = require 'sundown'
        local content = dokx._readFile(markdownFile)
        local rendered = sundown.render(content)
        if path.isfile(outputPath) then
            dokx.logger:warn("*** dokx.generateHTML: overwriting existing html file " .. outputPath .. " ***")
        end
        local outputFile = io.open(outputPath, 'w')
        dokx.logger:debug("dokx.generateHTML: writing to " .. outputPath)
        lapp.assert(outputFile, "Could not open: " .. outputPath)
        outputFile:write(rendered)
        outputFile:close()
    end

    for i, input in ipairs(inputs) do
        input = path.abspath(path.normpath(input))
        dokx.logger:info("dokx.generateHTML: processing file " .. input)
        local basename = path.basename(input)
        local packageName, ext = path.splitext(basename)
        lapp.assert(ext == '.md', "Expected .md file for input")
        local outputPath = path.join(output, packageName .. ".html")

        handleFile(input, outputPath)
    end
end

function dokx.extractTOC(package, output, inputs, config)
    if not path.isdir(output) then
        dokx.logger:info("Directory " .. output .. " not found; creating it.")
        path.mkdir(output)
    end

    for i, input in ipairs(inputs) do
        input = path.normpath(input)
        dokx.logger:info("dokx.extractTOC: processing file " .. input)

        local basename = path.basename(input)
        local packageName, ext = path.splitext(basename)
        lapp.assert(ext == '.lua', "Expected .lua file for input")
        local outputPath = path.join(output, packageName .. ".html")

        local content = dokx._readFile(input)
        local classes, documentedFunctions, undocumentedFunctions = dokx.extractDocs(package, input, content)

        -- Output markdown
        local output = ""

        if config.tocLevel == 'function' then
            if documentedFunctions:len() ~= 0 then
                output = output .. "<ul>\n"
                local function handleFunction(entity)
                    if not stringx.startswith(entity:name(), "_") then
                        anchorName = entity:fullname()
                        output = output .. [[<li><a href="#]] .. anchorName .. [[">]] .. entity:name() .. [[</a></li>]] .. "\n"
                    end
                end
                documentedFunctions:foreach(handleFunction)
                undocumentedFunctions:foreach(handleFunction)

                output = output .. "</ul>\n"
            end
        end

        local outputFile = io.open(outputPath, 'w')
        outputFile:write(output)
        outputFile:close()
    end

end

function dokx.combineTOC(package, input)
    dokx.logger:info("dokx.combineTOC: generating HTML ToC for " .. input)

    local outputName = "toc.html"

    if not path.isdir(input) then
        error("dokx.combineTOC: not a directory: " .. input)
    end

    local outputPath = path.join(input, outputName)

    -- Retrieve package name from path, by looking at the name of the last directory
    local sectionPaths = dir.getfiles(input, "*.html")
    local packageName = dokx._getLastDirName(input)

    local toc = "<ul>\n"
    sectionPaths:foreach(function(sectionPath)
        dokx.logger:info("dokx.combineTOC: adding " .. sectionPath .. " to ToC")
        toc = toc .. makeSectionTOC(package, sectionPath)
    end)
    toc = toc .. "</ul>\n"

    dokx.logger:info("dokx.combineTOC: writing to " .. outputPath)

    local outputFile = io.open(outputPath, 'w')
    outputFile:write(toc)
    outputFile:close()
end

function dokx.extractMarkdown(package, output, inputs)

    if not path.isdir(output) then
        dokx.logger:info("dokx.extractMarkdown: directory " .. output .. " not found; creating it.")
        path.mkdir(output)
    end

    for i, input in ipairs(inputs) do
        input = path.normpath(input)
        dokx.logger:info("dokx.extractMarkdown: processing file " .. input)

        local basename = path.basename(input)
        local packageName, ext = path.splitext(basename)
        lapp.assert(ext == '.lua', "Expected .lua file for input")
        local outputPath = path.join(output, packageName .. ".md")
        dokx.logger:info("dokx.extractMarkdown: writing to " .. outputPath)

        local content = dokx._readFile(input)
        local classes, documentedFunctions, undocumentedFunctions, fileString = dokx.extractDocs(
                package, input, content
            )

        -- Output markdown
        local writer = dokx.MarkdownWriter(outputPath, 'html') -- TODO
        local haveNonClassFunctions = false -- TODO

        if basename ~= 'init.lua' and fileString or haveNonClassFunctions then
            writer:heading(3, basename)
        end
        if fileString then
            writer:write(fileString .. "\n")
        end

        classes:foreach(func.bind1(writer.class, writer))
        documentedFunctions:foreach(func.bind1(writer.documentedFunction, writer))

        -- List undocumented functions, if there are any
        if undocumentedFunctions:len() ~= 0 then
            writer:heading(4, "Undocumented methods")
            undocumentedFunctions:foreach(func.bind1(writer.undocumentedFunction, writer))
        end

        writer:close()
    end
end

function dokx.generateHTMLIndex(input)
    dokx.logger:info("dokx.generateHTMLIndex: generating global documentation index for " .. input)

    if not path.isdir(input) then
        error("dokx.generateHTMLIndex: not a directory: " .. input)
    end

    local outputName = "index.html"
    local outputPath = path.join(input, outputName)
    local packageDirs = dir.getdirectories(input)
    local templateHTML = dokx._readFile("templates/packageIndex.html")
    local template = textx.Template(templateHTML)

    -- Construct package list HTML
    local packageList = "<ul>"
    packageDirs:foreach(function(packageDir)
        local packageName = path.basename(packageDir)
        dokx.logger:info("dokx.generateHTMLIndex: adding " .. packageName .. " to index")
        packageList = packageList .. indexEntry(packageName)
    end)
    packageList = packageList .. "</ul>"

    local output = template:safe_substitute { packageList = packageList }
    dokx.logger:info("dokx.generateHTMLIndex: writing to " .. outputPath)

    local outputFile = io.open(outputPath, 'w')
    outputFile:write(output)
    outputFile:close()
end

function dokx._getPackageLuaFiles(packagePath, config)
    local luaFiles = dir.getallfiles(packagePath, "*.lua")
    if config['filter'] then
        luaFiles = tablex.filter(luaFiles, function(x)
            local admit = string.find(x, config['filter'])
            if not admit then
                dokx.logger:info("dokx.buildPackageDocs: skipping file excluded by filter: " .. x)
            end
            return admit
        end)
    end
    return luaFiles
end

function dokx._getDokxDir()
    return path.dirname(debug.getinfo(1, 'S').source):sub(2)
end

function dokx.buildPackageDocs(outputRoot, packagePath)
    packagePath = path.abspath(path.normpath(packagePath))
    outputRoot = path.abspath(path.normpath(outputRoot))
    local config = dokx._loadConfig(packagePath)

    if not path.isdir(outputRoot) then
        error("dokx.buildPackageDocs: invalid documentation tree " .. outputRoot)
    end
    local docTmp = dokx._mkTemp()
    local tocTmp = dokx._mkTemp()

    local packageName = dokx._getLastDirName(packagePath)
    local luaFiles = dokx._getPackageLuaFiles(packagePath, config)

    local extraMarkdownFiles = dir.getallfiles(packagePath, "*.md")
    local markdownFiles = tablex.map(func.compose(prependPath(docTmp), luaToMd), luaFiles)
    local outputPackageDir = path.join(outputRoot, packageName)

    dokx.logger:info("dokx.buildPackageDocs: examining package " .. packagePath)
    dokx.logger:info("dokx.buildPackageDocs: package name = " .. packageName)
    dokx.logger:info("dokx.buildPackageDocs: output root = " .. outputRoot)
    dokx.logger:info("dokx.buildPackageDocs: output dir = " .. outputPackageDir)

    path.mkdir(outputPackageDir)

    dokx.extractMarkdown(packageName, docTmp, luaFiles)
    dokx.extractTOC(packageName, tocTmp, luaFiles, config)
    dokx.combineTOC(packageName, tocTmp)
    dokx.generateHTML(outputPackageDir, markdownFiles)
    dokx.generateHTML(path.join(outputPackageDir, "extra"), extraMarkdownFiles)
    dokx.combineHTML(path.join(tocTmp, "toc.html"), outputPackageDir, config)

    -- Find the path to the templates - it's relative to our installed location
    local dokxDir = dokx._getDokxDir()
    local pageStyle = path.join(dokxDir, "templates/style-page.css")
    file.copy(pageStyle, path.join(outputPackageDir, "style.css"))

    -- Update the main index
    dokx.generateHTMLIndex(outputRoot)
    file.copy(path.join(dokxDir, "templates/style-index.css"), path.join(outputRoot, "style.css"))

    dir.rmtree(docTmp)
    dir.rmtree(tocTmp)

    dokx.logger:info("Installed docs for " .. packagePath)
end
