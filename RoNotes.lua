--[[
TODO:

- indicator for when someone hasn't chosen a location







- Maybe add a redundancy to saving, checking the current RoNotes UI folder if they match
up with the plugins save setting

^ Which would have to come with an option to delete place notes

- 

]]

local SearchNote = require(script.Parent.SearchNoteList)

local userInputService = game:GetService("UserInputService")
local tweenService = game:GetService("TweenService")
local httpService = game:GetService("HttpService")
local physicsService = game:GetService("PhysicsService")
local runService = game:GetService("RunService")
local studioService = game:GetService("StudioService")
local changeHistoryService = game:GetService("ChangeHistoryService")
local coreGui = game:GetService("CoreGui")

local toolbar = plugin:CreateToolbar("RoNotes")
local notesButton = toolbar:CreateButton("RoNotes", "RoNotes", "rbxassetid://8305988003")

local widgetSettings = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float,false,false,300,225,300,200)
local RoNotesUI = plugin:CreateDockWidgetPluginGui("RoNotesMain", widgetSettings)
RoNotesUI.Title = "RoNotes"
RoNotesUI.Name = "RoNotes"
if not plugin:GetSetting("topBarSize") then
	plugin:SetSetting("topBarSize",50)
end
if not plugin:GetSetting("noteSize") then
	plugin:SetSetting("noteSize",50)
end

local topBarSize = plugin:GetSetting("topBarSize") -- Pixels
local noteSize = plugin:GetSetting("noteSize")
local debounce = false

local mainScreen = nil
local noteCreationScreen = nil
local addNewNote : () -> () = nil
local addNotes : (fromFile : boolean,sortOrder : {{string}}?) -> () = nil
local RoNotesUiFolder : Folder
local RoNotesPositionFolder : Folder
local fileFound = true





-- Check if studio is in Edit mode so that we can remove
-- the notes during play test. RunService:IsEdit()

type ConnectionStruct = {
	menu : RBXScriptConnection,
	visibility : RBXScriptConnection,
	delete : RBXScriptConnection,
	sliderCheckClick : RBXScriptConnection,
	sliderMoved : RBXScriptConnection,
	sliderCheckUnClick : RBXScriptConnection,
	inSlider : RBXScriptConnection
}

type NoteFrameStruct = {
	frame : Frame,
	visibility : RBXScriptConnection,
	visibilityMouseEntered : RBXScriptConnection,
	visibilityMouseLeft : RBXScriptConnection,
	delete : RBXScriptConnection,
	deleteMouseEntered : RBXScriptConnection,
	deleteMouseLeft : RBXScriptConnection,
	zoomTo : RBXScriptConnection,
	zoomToMouseEntered : RBXScriptConnection,
	zoomToMouseLeft : RBXScriptConnection
}


type Note = {
	id : string,
	timeCreated : number,
	title : string,
	position : Vector3,
	owner : string,
	visible : boolean,
	frameInfo : NoteFrameStruct,
	billboardUIConnections : ConnectionStruct | nil
}


local NoteList : {Note} = {}
local NoteFrameList = {}

local function DeleteNoteFrame(note : Note)
	if note.frameInfo then
		if note.frameInfo.visibility then
			note.frameInfo.visibility:Disconnect()
		end
		if note.frameInfo.visibilityMouseEntered then
			note.frameInfo.visibilityMouseEntered:Disconnect()
		end
		if note.frameInfo.visibilityMouseLeft then
			note.frameInfo.visibilityMouseLeft:Disconnect()
		end
		if note.frameInfo.delete then
			note.frameInfo.delete:Disconnect()
		end
		if note.frameInfo.deleteMouseEntered then
			note.frameInfo.deleteMouseEntered:Disconnect()
		end
		if note.frameInfo.deleteMouseLeft then
			note.frameInfo.deleteMouseLeft:Disconnect()
		end
		if note.frameInfo.zoomTo then
			note.frameInfo.zoomTo:Disconnect()
		end
		if note.frameInfo.zoomToMouseEntered then
			note.frameInfo.zoomToMouseEntered:Disconnect()
		end
		if note.frameInfo.zoomToMouseLeft then
			note.frameInfo.zoomToMouseLeft:Disconnect()
		end
		if note.frameInfo.frame then
			note.frameInfo.frame:Destroy()
		end
	end
end

local function CloseBillBoardConnections(note)
	if note.billboardUIConnections then
		if note.billboardUIConnections.delete then
			note.billboardUIConnections.delete:Disconnect()
		end
		if note.billboardUIConnections.visibility then
			note.billboardUIConnections.visibility:Disconnect()
		end
		if note.billboardUIConnections.menu then
			note.billboardUIConnections.menu:Disconnect()
		end
		if note.billboardUIConnections.inSlider then
			note.billboardUIConnections.inSlider:Disconnect()
		end
		if note.billboardUIConnections.sliderCheckClick then
			note.billboardUIConnections.sliderCheckClick:Disconnect()
		end
		if note.billboardUIConnections.sliderCheckUnClick then
			note.billboardUIConnections.sliderCheckUnClick:Disconnect()
		end
		if note.billboardUIConnections.sliderMoved then
			note.billboardUIConnections.sliderMoved:Disconnect()
		end
		note.billboardUIConnections = nil
	end
end

local function NoteFromID(noteId)
	for i,v in pairs(NoteList) do
		if v.id == noteId then
			return i,v	
		end
	end
	return nil
end

local function PermanentDeleteNote(noteId)
	
	local noteIndex,note = NoteFromID(noteId)
	if note then
		
		CloseBillBoardConnections(note)
		DeleteNoteFrame(note)
		
		local NoteLocation = RoNotesPositionFolder:FindFirstChild(noteId)
		if NoteLocation then
			NoteLocation:Destroy()
		end
		local NoteBillboard = RoNotesUiFolder:FindFirstChild(noteId)
		if NoteBillboard then
			NoteBillboard:Destroy()
		end
		NoteList[noteIndex] = nil
	end
end

local function CreateMainScreen()
	mainScreen = script.Frame.MainFrame:Clone()
	mainScreen.Parent = RoNotesUI
	local addNoteEvent = mainScreen.InfoFrame.AddNew.TextButton.MouseButton1Click:Connect(addNewNote)
	local searchText = mainScreen.SearchFrame.InnerFrame.TextBox:GetPropertyChangedSignal("Text"):Connect(function(text)
		local searchString = mainScreen.SearchFrame.InnerFrame.TextBox.Text
		local searchList = {}
		for i,v : Note in pairs(NoteList) do
			searchList[i] = {}
			searchList[i].id = v.id
			searchList[i].title = v.title
		end
		
		local probabilities = SearchNote:SearchList(searchString,searchList)
		-- delete all frames
		for i,v in pairs(NoteList) do
			
			DeleteNoteFrame(v)
		end
		addNotes(false,probabilities)
		
	end)
	if fileFound then
		addNotes(true)
		fileFound = false
	else
		addNotes(false)
	end
end


local NoteScreenTextFits : RBXScriptConnection | nil
local NoteScreenTextArea : RBXScriptConnection | nil
local NoteScreenLocation : RBXScriptConnection | nil
local NoteScreenBackButton : RBXScriptConnection | nil
local NoteScreenBackButtonEnter : RBXScriptConnection | nil
local NoteScreenBackButtonLeave : RBXScriptConnection | nil
local textBoundsChangedEvent : RBXScriptConnection | nil
local submitButtonEvent : RBXScriptConnection | nil
local mouseMovedEvent : RBXScriptConnection | nil
local inputEnded : RBXScriptConnection | nil
local part = nil
local arrow = nil

local function CloseNoteScreen()
	pcall(function() runService:UnbindFromRenderStep("ArrowPhysics") end)
	if noteCreationScreen then
		noteCreationScreen:Destroy()
		if part then
			part:Destroy()
			part = nil
		end
		if arrow then
			arrow:Destroy()
			arrow = nil
		end
		if NoteScreenLocation then
			NoteScreenLocation:Disconnect()
			NoteScreenLocation = nil
		end
		if textBoundsChangedEvent then
			textBoundsChangedEvent:Disconnect()
			textBoundsChangedEvent = nil
		end
		if NoteScreenTextArea then
			NoteScreenTextArea:Disconnect()
			NoteScreenTextArea = nil
		end
		if NoteScreenTextFits then
			NoteScreenTextFits:Disconnect()
			NoteScreenTextFits = nil
		end
		if submitButtonEvent then
			submitButtonEvent:Disconnect()
			submitButtonEvent = nil
		end
		if NoteScreenBackButton then
			NoteScreenBackButton:Disconnect()
			NoteScreenBackButton = nil
		end
		if NoteScreenBackButtonEnter then
			NoteScreenBackButtonEnter:Disconnect()
			NoteScreenBackButtonEnter = nil
		end
		if NoteScreenBackButtonLeave then
			NoteScreenBackButtonLeave:Disconnect()
			NoteScreenBackButtonLeave = nil
		end
		
	end
end

local function CreateNoteBillboardConnections(NoteUi,NoteIndex,adornee) -- that's an unnecessarily long function header lol
	if adornee then
		NoteUi.Adornee = adornee
	end
	local topBarBillboard = NoteUi.Frame.TopBar
	local billboardMenuDebounce = false
	local note = NoteList[NoteIndex]
	note.billboardUIConnections = {
		visibility = nil,
		delete = nil,
		menu = nil,
		sliderCheckClick = nil,
		sliderMoved = nil,
		sliderCheckUnClick = nil,
		inSlider = nil
	}
	note.billboardUIConnections.menu = topBarBillboard.Menu.MouseButton1Click:Connect(function()
		if not billboardMenuDebounce then
			local menu = NoteUi.Frame.Menu
			menu.Visible = true
			
			note.billboardUIConnections.visibility = menu.visibility.MouseButton1Click:Connect(function()
				
				note.visible = not note.visible
				menu.Visible = note.visible
				
				if note.billboardUIConnections.delete then
					note.billboardUIConnections.delete:Disconnect()
				end
				
				if note.billboardUIConnections.visibility then
					note.billboardUIConnections.visibility:Disconnect()
				end
				
				if note.billboardUIConnections.menu then
					note.billboardUIConnections.menu:Disconnect()
				end
				
				if note.billboardUIConnections.inSlider then
					note.billboardUIConnections.inSlider:Disconnect()
				end
				if note.billboardUIConnections.sliderCheckClick then
					note.billboardUIConnections.sliderCheckClick:Disconnect()
				end
				if note.billboardUIConnections.sliderCheckUnClick then
					note.billboardUIConnections.sliderCheckUnClick:Disconnect()
				end
				if note.billboardUIConnections.sliderMoved then
					note.billboardUIConnections.sliderMoved:Disconnect()
				end
				
				if NoteList[NoteIndex].frameInfo then
					if NoteList[NoteIndex].frameInfo.frame then
						local visibility : ImageButton = NoteList[NoteIndex].frameInfo.frame:FindFirstChild("visibility") :: ImageButton
						if visibility then
							visibility.ImageRectOffset = Vector2.new(564, 44)
						end
					end
				end
				NoteList[NoteIndex].visible = false
				NoteUi.Enabled = false
			end)
			
			note.billboardUIConnections.delete = menu.delete.MouseButton1Click:Connect(function()
				PermanentDeleteNote(NoteList[NoteIndex].id)
			end)
			
			
			billboardMenuDebounce = true
			
		else
			local menu = NoteUi.Frame.Menu
			menu.Visible = false
			
			if note.billboardUIConnections.visibility then
				note.billboardUIConnections.visibility:Disconnect()
			end
			if note.billboardUIConnections.delete then
				note.billboardUIConnections.delete:Disconnect()
			end
			billboardMenuDebounce = false
			
		end
	end)
	
	local sliderThumb = NoteUi.Frame.FontSizeFrame.SliderFrame.SliderThumb
	
	note.billboardUIConnections.inSlider = sliderThumb.MouseEnter:Connect(function()
		if not note.billboardUIConnections.sliderCheckClick then
			note.billboardUIConnections.sliderCheckClick = userInputService.InputBegan:Connect(function(inputObject,processed)
				if inputObject.UserInputType == Enum.UserInputType.MouseButton1 and inputObject.UserInputState == Enum.UserInputState.Begin then
					note.billboardUIConnections.sliderMoved = NoteUi.Frame.FontSizeFrame.PseudoMouseMoved.MouseMoved:Connect(function(x,y)
						
						local maxMoveX = NoteUi.Frame.FontSizeFrame.SliderFrame.AbsoluteSize.X
						local xScale = x / maxMoveX - 0.15
						
						local maxX = 0.85
						local minX = 0.1
						
						local barPos = math.clamp(xScale,0,1)
						sliderThumb.Position = UDim2.new(barPos,0,sliderThumb.Position.Y.Scale,0)
						
						local textAreaBillboard = NoteUi.Frame.TextArea
						local text = textAreaBillboard.ScrollingFrame.NoteDesc.Text
						
						if barPos < 0.5 then
							barPos = 0.05 + (barPos / 10)
						elseif barPos > 0.5 then
							barPos = barPos - 0.4
						elseif barPos == 0.5 then
							barPos = 0.1 -- Default
						end
						
						local sentenceSize = 500 * (barPos * 10)
						local MAX_CHARS = 19
						local multiplier = math.ceil(string.len(text) / MAX_CHARS)
						local canvasSize = (sentenceSize * multiplier) / 5000
						if canvasSize < 1 then
							textAreaBillboard.ScrollingFrame.NoteDesc.Size = UDim2.new(1,0,(sentenceSize * multiplier) / 5000,0)
						else
							textAreaBillboard.ScrollingFrame.NoteDesc.Size = UDim2.new(1,0,1,0)
						end
						textAreaBillboard.ScrollingFrame.CanvasSize = UDim2.new(1,0,canvasSize,0)
						--print(x,y)
					end)
				end
			end)
			note.billboardUIConnections.sliderCheckUnClick = userInputService.InputEnded:Connect(function(inputObject,processed)
				if inputObject.UserInputType == Enum.UserInputType.MouseButton1 and inputObject.UserInputState == Enum.UserInputState.End then
					--print("run")
					if note.billboardUIConnections.sliderMoved then
						note.billboardUIConnections.sliderMoved:Disconnect()
						note.billboardUIConnections.sliderMoved = nil
					end
					
					if note.billboardUIConnections.sliderCheckClick then
						note.billboardUIConnections.sliderCheckClick:Disconnect()
						note.billboardUIConnections.sliderCheckClick = nil
					end
					
					if note.billboardUIConnections.sliderCheckUnClick then
						note.billboardUIConnections.sliderCheckUnClick:Disconnect()
						note.billboardUIConnections.sliderCheckUnClick = nil
					end
				end
			end)
		end
	end)
end

local function CreateNoteFrameConnections(note : Note, order : number?)
	local newNoteCard = script.NotePlaceHolder:Clone()
	
	note.frameInfo = {
		frame = nil,
		visibility = nil,
		visibilityMouseEntered = nil,
		visibilityMouseLeft = nil,
		delete = nil,
		deleteMouseEntered = nil,
		deleteMouseLeft = nil,
		zoomTo = nil,
		zoomToMouseEntered = nil,
		zoomToMouseLeft = nil
	}
	if order then
		newNoteCard.LayoutOrder = order
	end
	newNoteCard.title.Text = note.title
	note.frameInfo.delete = newNoteCard.delete_forever.MouseButton1Click:Connect(function()
		PermanentDeleteNote(note.id)
	end)
	local deleteTween = nil
	note.frameInfo.deleteMouseEntered = newNoteCard.delete_forever.MouseEnter:Connect(function()
		deleteTween = tweenService:Create(newNoteCard.delete_forever,TweenInfo.new(0.5),{ImageColor3 = Color3.fromRGB(138, 0, 0)}):Play()
	end)
	note.frameInfo.deleteMouseLeft = newNoteCard.delete_forever.MouseLeave:Connect(function()
		deleteTween = tweenService:Create(newNoteCard.delete_forever,TweenInfo.new(0.5),{ImageColor3 = Color3.fromRGB(255,0,0)}):Play()
	end)
	
	note.frameInfo.visibility = newNoteCard.visibility.MouseButton1Click:Connect(function()
		local uiNote = RoNotesUiFolder:FindFirstChild(note.id)
		if uiNote then
			note.visible = not note.visible -- invert visibility
			uiNote.Enabled = note.visible
			if uiNote.Frame then
				uiNote.Frame.Menu.Visible = false
			end
			
			if note.visible then
				newNoteCard.visibility.ImageRectOffset = Vector2.new(84, 44)
				for i,v in pairs(NoteList) do
					if v.id == note.id then
						local position = RoNotesPositionFolder:FindFirstChild(note.id)
						local ui = RoNotesUiFolder:FindFirstChild(v.id)
						
						if position and ui then
							CreateNoteBillboardConnections(RoNotesUiFolder:FindFirstChild(v.id),i,RoNotesPositionFolder:FindFirstChild(note.id)) 
						end	
					end
				end
				
			else
				newNoteCard.visibility.ImageRectOffset = Vector2.new(564, 44)
				if note.billboardUIConnections then
					if note.billboardUIConnections.visibility then
						note.billboardUIConnections.visibility:Disconnect()
					end
					
					if note.billboardUIConnections.delete then
						note.billboardUIConnections.delete:Disconnect()
					end
					
					if note.billboardUIConnections.menu then
						note.billboardUIConnections.menu:Disconnect()
					end
					if note.billboardUIConnections.inSlider then
						note.billboardUIConnections.inSlider:Disconnect()
					end
					if note.billboardUIConnections.sliderCheckClick then
						note.billboardUIConnections.sliderCheckClick:Disconnect()
					end
					if note.billboardUIConnections.sliderCheckUnClick then
						note.billboardUIConnections.sliderCheckUnClick:Disconnect()
					end
					if note.billboardUIConnections.sliderMoved then
						note.billboardUIConnections.sliderMoved:Disconnect()
					end
				end
			end
		end
	end)
	local visibilityTween = nil
	
	note.frameInfo.visibilityMouseEntered = newNoteCard.visibility.MouseEnter:Connect(function()
		visibilityTween = tweenService:Create(newNoteCard.visibility,TweenInfo.new(0.5),{ImageColor3 = Color3.fromRGB(66,66,66)}):Play()
	end)
	note.frameInfo.visibilityMouseLeft = newNoteCard.visibility.MouseLeave:Connect(function()
		visibilityTween = tweenService:Create(newNoteCard.visibility,TweenInfo.new(0.5),{ImageColor3 = Color3.fromRGB(121,121,121)}):Play()
	end)
	local offset = Vector3.new(0, 6, 6)
	note.frameInfo.zoomTo = newNoteCard.zoomTo.MouseButton1Click:Connect(function()
		local notePosition = RoNotesPositionFolder:FindFirstChild(note.id)
		if notePosition and notePosition:IsA("BasePart") then
			game.Workspace.Camera.CFrame = CFrame.new(notePosition.Position + offset)
			game.Workspace.Camera.Focus = (notePosition.CFrame * CFrame.new(0,6,0))
		end
	end)
	
	local zoomToTween = nil
	note.frameInfo.zoomToMouseEntered = newNoteCard.zoomTo.MouseEnter:Connect(function()	
		zoomToTween = tweenService:Create(newNoteCard,TweenInfo.new(0.4),{BackgroundColor3 = Color3.fromRGB(185, 162, 94)}):Play()
	end)
	
	note.frameInfo.zoomToMouseLeft = newNoteCard.zoomTo.MouseLeave:Connect(function()
		zoomToTween = tweenService:Create(newNoteCard,TweenInfo.new(0.4),{BackgroundColor3 = Color3.fromRGB(255, 224, 130)}):Play()
	end)
	
	note.frameInfo.frame = newNoteCard
	if mainScreen then
		newNoteCard.Parent = mainScreen.NotesFrame.NotesList	
	end
	
end

addNotes = function(fromFile : boolean, sortOrder : {{string}}?)
	if fromFile then
		for i,v in pairs(RoNotesUiFolder:GetChildren()) do
			-- have to add the notes first
			local noteInfo = v.NoteInfo
			table.insert(NoteList,{
				id = noteInfo:GetAttribute("id"),
				timeCreated = noteInfo:GetAttribute("timeCreated"),
				title = noteInfo:GetAttribute("title"),
				visible = noteInfo:GetAttribute("visible"),
				position = noteInfo:GetAttribute("position"),
				owner = noteInfo:GetAttribute("owner"),
				frameInfo = nil,
				billboardUIConnections = nil
			})
			local NoteIndex = #NoteList
			local NoteAdornee : Part = RoNotesPositionFolder:FindFirstChild(NoteList[NoteIndex].id) :: Part
			if not NoteAdornee then
				NoteAdornee = Instance.new("Part")
				
				NoteAdornee.Shape = Enum.PartType.Ball
				NoteAdornee.Size = Vector3.new(0.01,0.01,0.01)
				NoteAdornee.Position = NoteList[NoteIndex].position
				NoteAdornee.Anchored = true
				NoteAdornee.Locked = true
				
				NoteAdornee.Parent = workspace
			end
			CreateNoteFrameConnections(NoteList[NoteIndex])
			CreateNoteBillboardConnections(v,NoteIndex,NoteAdornee) 
		end
		
	else
		
		local counter = 0
		for i,v in pairs(NoteList) do
			if sortOrder then
				for k,j in pairs(sortOrder) do
					if j[1] == v.id then
						CreateNoteFrameConnections(v,k)
					end 
				end
				
			else
				CreateNoteFrameConnections(v)
			end
			
		end
	end
end

function CheckDupe(originalName : string, name : string, counter : number)
	for i,v in pairs(NoteList) do
		if v.title == name then
			name = originalName .. " (".. counter ..")"
			return CheckDupe(originalName,name,counter + 1)
		end
	end
	return name
end

local function CreateNoteScreen()
	
	
	noteCreationScreen = script.Frame.NoteCreationScreen:Clone()
	noteCreationScreen.Parent = RoNotesUI
	
	local scrollFrame = noteCreationScreen.CreationFrame["1"].NoteTextScroll
	local textArea : TextBox = scrollFrame.TextBox
	local locationButton = noteCreationScreen.CreationFrame["2"].TextButton
	local submitButton = noteCreationScreen.CreationFrame["3"]
	
	NoteScreenBackButton = noteCreationScreen.InfoFrame.backspace.MouseButton1Click:Connect(function()
		CloseNoteScreen()
		CreateMainScreen()
	end)
	
	NoteScreenBackButtonEnter = noteCreationScreen.InfoFrame.backspace.MouseEnter:Connect(function()
		tweenService:Create(noteCreationScreen.InfoFrame.backspace,TweenInfo.new(0.1),{ImageColor3 = Color3.fromRGB(173, 143, 53)}):Play()
	end)
	
	NoteScreenBackButtonLeave = noteCreationScreen.InfoFrame.backspace.MouseLeave:Connect(function()
		tweenService:Create(noteCreationScreen.InfoFrame.backspace,TweenInfo.new(0.1),{ImageColor3 = Color3.fromRGB(255, 213, 79)}):Play()
	end)
	
	local function textFits()
		if not textArea.TextFits then
			textArea.Size = UDim2.new(textArea.Size.X.Scale, textArea.Size.X.Offset, textArea.Size.Y.Scale, textArea.Size.Y.Offset + textArea.TextSize)
			scrollFrame.CanvasSize = UDim2.new(scrollFrame.CanvasSize.X.Scale, scrollFrame.CanvasSize.X.Offset, scrollFrame.CanvasSize.Y.Scale, scrollFrame.AbsoluteCanvasSize.Y + textArea.TextSize)
			tweenService:Create(scrollFrame,TweenInfo.new(0.1),{CanvasPosition = Vector2.new(0, scrollFrame.CanvasSize.Y.Offset - scrollFrame.AbsoluteWindowSize.Y)}):Play()
			
			textFits()	
		else
			if textArea.TextBounds.Y < textArea.AbsoluteSize.Y then
				textArea.Size = UDim2.new(textArea.Size.X.Scale,textArea.Size.X.Offset,textArea.Size.Y.Scale,textArea.TextBounds.Y)
				scrollFrame.CanvasSize = UDim2.new(scrollFrame.CanvasSize.X.Scale, scrollFrame.CanvasSize.X.Offset, scrollFrame.CanvasSize.Y.Scale, textArea.Size.Y.Offset)
			end
			return
		end
	end
	local focus = false
	
	runService.Heartbeat:Connect(function()
		
		if textArea:IsFocused() then
			textFits()
		end
	end)
	
	local mouse : PluginMouse = plugin:GetMouse()
	NoteScreenLocation = locationButton.MouseButton1Click:Connect(function()
		
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Blacklist
		params.FilterDescendantsInstances = {workspace.RoNotes_IMPORTANT}
		params.IgnoreWater = true
		
		if part then
			part:Destroy()
			pcall(function() runService:UnbindFromRenderStep("ArrowPhysics") end)
		end
		if arrow then
			arrow:Destroy()
		end
		if inputEnded then
			inputEnded:Disconnect()
		end
		if mouseMovedEvent then
			mouseMovedEvent:Disconnect()
		end
		
		part = Instance.new("Part")
		part.Shape = Enum.PartType.Ball
		part.Color = Color3.fromRGB(0,255,0)
		part.Size = Vector3.new(1,1,1)
		part.Anchored = true
		part.Name = "Temp"
		part.CastShadow = false
		part.Material = Enum.Material.ForceField
		part.Locked = true
		part.Parent = workspace.RoNotes_IMPORTANT
		arrow = script.Arrow:Clone()
		arrow.Locked = true
		arrow.Name = "Temp"
		arrow.Parent = RoNotesPositionFolder
		
		mouseMovedEvent = runService.RenderStepped:Connect(function()
			local mouseRay = mouse.UnitRay
			
			local rayResult = workspace:Raycast(mouseRay.Origin,mouseRay.Direction * 500,params)
			
			if rayResult then
				if part then
					part.CFrame = CFrame.lookAt(rayResult.Position,Vector3.new(0,0,0),rayResult.Normal)
				end
			end
		end)
		
		local springConstant = 0.1
		local friction = 0.3
		local velocity = Vector3.new(0,0,0)
		runService:BindToRenderStep("ArrowPhysics",Enum.RenderPriority.Camera.Value,function(delta)
			if part and arrow then
				local displacement = (arrow.Position - (part.Position + Vector3.new(0,3,0)))
				local force = displacement * springConstant
				velocity = (velocity * (1 - friction)) - force
				arrow.CFrame += velocity
			end
		end)
		
		
		inputEnded = userInputService.InputEnded:Connect(function(input : InputObject, processed : boolean)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				if mouseMovedEvent then
					mouseMovedEvent:Disconnect()
				end
				local mouseRay = mouse.UnitRay
				
				local rayResult = workspace:Raycast(mouseRay.Origin,mouseRay.Direction * 500,params)
				
				if rayResult then
					pcall(function() runService:UnbindFromRenderStep("ArrowPhysics") end)
					part.CFrame = CFrame.lookAt(rayResult.Position,Vector3.new(0,0,0),rayResult.Normal)
					arrow.Position = part.Position + Vector3.new(0,3,0)
					if inputEnded then
						inputEnded:Disconnect()
						inputEnded = nil
					end
					if mouseMovedEvent then
						mouseMovedEvent:Disconnect()
						mouseMovedEvent = nil
					end
					locationButton.BorderSizePixel = 0
				end
			end
		end)
	end)
	
	submitButtonEvent = submitButton.MouseButton1Click:Connect(function()
		
		if part then
			changeHistoryService:SetWaypoint("CreateNoteBegin")
			part.Size = Vector3.new(0.01,0.01,0.01)
			part.Transparency = 1
			
			local timeNoteCreated = os.time()
			local id = httpService:GenerateGUID()
			
			local NoteAdornee = part:Clone()
			NoteAdornee.Name = id
			NoteAdornee.Parent = RoNotesPositionFolder
			part:Destroy()
			
			if arrow then
				arrow:Destroy()
			end
			local endTitle = noteCreationScreen.CreationFrame["1"].Topbar.TitleBox.Text
			if endTitle == "" then
				endTitle = "Untitled Note"
			end
			
			endTitle = CheckDupe(endTitle,endTitle,1)
			
			table.insert(NoteList,{
				id = id,
				timeCreated = timeNoteCreated,
				title = endTitle,
				visible = true,
				owner = tostring(studioService:GetUserId()),
				position = NoteAdornee.Position,
				frameInfo = nil,
				billboardUIConnections = nil
			})
			local NoteIndex = #NoteList
			
			local noteInfo = Instance.new("Folder")
			noteInfo.Name = "NoteInfo"
			noteInfo:SetAttribute("id",id)
			noteInfo:SetAttribute("timeCreated",timeNoteCreated)
			noteInfo:SetAttribute("title",endTitle)
			noteInfo:SetAttribute("owner",tostring(studioService:GetUserId()))
			noteInfo:SetAttribute("visible",true)
			noteInfo:SetAttribute("position",NoteAdornee.Position)
			
			local NoteUi = script.PhysicalNote:Clone()
			
			
			NoteUi.Name = id
			noteInfo.Parent = NoteUi
			NoteUi.Parent = RoNotesUiFolder
			
			local text = textArea.Text
			local textAreaBillboard = NoteUi.Frame.TextArea
			textAreaBillboard.ScrollingFrame.NoteDesc.Text = text
			
			local sentenceSize = 500
			local MAX_CHARS = 19
			local multiplier = math.ceil(string.len(text) / MAX_CHARS)
			local canvasSize = (sentenceSize * multiplier) / 5000
			if canvasSize < 1 then
				textAreaBillboard.ScrollingFrame.NoteDesc.Size = UDim2.new(1,0,(sentenceSize * multiplier) / 5000,0)
			else
				textAreaBillboard.ScrollingFrame.NoteDesc.Size = UDim2.new(1,0,1,0)
			end
			textAreaBillboard.ScrollingFrame.CanvasSize = UDim2.new(1,0,canvasSize,0)
			
			local topBarBillboard = NoteUi.Frame.TopBar
			topBarBillboard.TitleText.Text = endTitle
			
			CreateNoteBillboardConnections(NoteUi,NoteIndex,NoteAdornee) 
			CloseNoteScreen()
			CreateMainScreen()
			changeHistoryService:SetWaypoint("CreateNoteEnd")
		else
			locationButton.BorderColor3 = Color3.fromRGB(214, 0, 0)
			locationButton.BorderSizePixel = 2
			locationButton.BorderMode = Enum.BorderMode.Inset
		end
	end)
end

local function CloseMainScreen()
	if mainScreen then
		mainScreen:Destroy()
	end
	for i,v : Note in pairs(NoteList) do
		if v.frameInfo then
			if v.frameInfo.visibility then
				v.frameInfo.visibility:Disconnect()
			end
			if v.frameInfo.visibilityMouseEntered then
				v.frameInfo.visibilityMouseEntered:Disconnect()
			end
			if v.frameInfo.visibilityMouseLeft then
				v.frameInfo.visibilityMouseLeft:Disconnect()
			end
			if v.frameInfo.delete then
				v.frameInfo.delete:Disconnect()
			end
			if v.frameInfo.deleteMouseEntered then
				v.frameInfo.deleteMouseEntered:Disconnect()
			end
			if v.frameInfo.deleteMouseLeft then
				v.frameInfo.deleteMouseLeft:Disconnect()
			end
			if v.frameInfo.zoomTo then
				v.frameInfo.zoomTo:Disconnect()
			end
			if v.frameInfo.zoomToMouseEntered then
				v.frameInfo.zoomToMouseEntered:Disconnect()
			end
			if v.frameInfo.zoomToMouseLeft then
				v.frameInfo.zoomToMouseLeft:Disconnect()
			end
			if v.frameInfo.frame then
				v.frameInfo.frame:Destroy()
			end
			v.frameInfo.frame:Destroy()
		end
	end
end


addNewNote = function()
	
	mainScreen:Destroy()
	CreateNoteScreen()
end

local function ClearScreens()
	CloseMainScreen()
	CloseNoteScreen()
	
end
local distanceCheck = nil
notesButton.Click:Connect(function()
	if not debounce then
		RoNotesUiFolder = game:GetService("CoreGui"):FindFirstChild("RoNotes_IMPORTANT")
		RoNotesPositionFolder = game.Workspace:FindFirstChild("RoNotes_IMPORTANT")
		if not RoNotesUiFolder then
			RoNotesUiFolder = Instance.new("Folder")
			RoNotesUiFolder.Name = "RoNotes_IMPORTANT"
			RoNotesUiFolder.Parent = game:GetService("CoreGui")
			RoNotesUiFolder.Archivable = false
			fileFound = false
		end
		
		if not RoNotesPositionFolder then
			RoNotesPositionFolder = Instance.new("Folder")
			RoNotesPositionFolder.Name = "RoNotes_IMPORTANT"
			RoNotesPositionFolder.Parent = game.Workspace
			RoNotesPositionFolder.Archivable = false
		end
		local oldPosition = nil

		CreateMainScreen()
		debounce = true
		RoNotesUI.Enabled = true
		plugin:Activate(false)
		notesButton:SetActive(true)
		game.Workspace.Camera:GetPropertyChangedSignal("CFrame"):Connect(function()
			if oldPosition ~= game.Workspace.Camera.CFrame.Position then
				for i,v in pairs(RoNotesUiFolder:GetChildren()) do
					if v:IsA("BillboardGui") then
						if v.Adornee then
							local noteIndex, note = NoteFromID(v.Name)
							if note then
								if (v.Adornee.CFrame.Position - game.Workspace.Camera.CFrame.Position).Magnitude < 50 then
									if not note.billboardUIConnections then
										CreateNoteBillboardConnections(v,noteIndex,nil)
									end
								else
									if note.billboardUIConnections then
										CloseBillBoardConnections(note)
									end
								end
							end
						end
					end
				end
				oldPosition = game.Workspace.Camera.CFrame.Position
			end
			
		end)
	else
		if distanceCheck then
			distanceCheck:Disconnect()
		end
		ClearScreens()
		debounce = false
		RoNotesUI.Enabled = false
		plugin:Deactivate()
		notesButton:SetActive(false)
	end
end)

RoNotesUI:BindToClose(function()
	ClearScreens()
	debounce = false
	RoNotesUI.Enabled = false
	plugin:Deactivate()
	notesButton:SetActive(false)
end)

