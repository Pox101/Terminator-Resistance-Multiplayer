-- Adds a native-styled entry without modifying or redistributing game assets.
-- Steam lobby/invitation UI is a separate milestone from online game transport.
return function(H,C,emit,online)
    local State=require('lobby_state')
    local base='/Game/UI/Menu/MainMenu/WB_MainMenuButton.WB_MainMenuButton_C'
    local menu,entry,panel,status,inviteButton,backButton,startButton
    local hooked,pending,lastSubmenu=false,nil,false
    local nextScan,nextPoll=0,0
    local native,steamState
    local function valid(o)return o~=nil and o:IsValid()end
    local function loadNative()
        if native then return true end
        local path=C.directory..'/steam_lobby.dll'
        local api={}
        for _,name in ipairs({'create','poll','leave'}) do
            local fn,err=package.loadlib(path,'lobby_'..name)
            if not fn then emit('steam_lobby_unavailable='..tostring(err));return false end
            api[name]=fn
        end
        native=api;return true
    end
    local function label(button,text)
        button.ButtonName=FText(text);button.ButtonNameTemp=FText(text)
        button.WB_StaticText.Text=FText(text)
        button.WB_StaticText.TextBlock_0:SetText(FText(text))
        button.WB_StaticText.TextBlock_NoWrap:SetText(FText(text))
    end
    local function button(pc,text)
        local b=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary'):Create(pc,StaticFindObject(base),pc)
        assert(valid(b),'Main menu button creation failed')
        label(b,text);return b
    end
    local function close(keepParty)
        if not keepParty then
            if online then online.leave() elseif native then native.leave() end
        end
        if valid(panel) then panel:RemoveFromParent() end
        panel,status,inviteButton,backButton,startButton=nil,nil,nil,nil,nil
        if valid(menu) then menu.VerticalBox_MenuItems:SetIsEnabled(true);menu.NavigationUnlocked=true end
        if valid(entry) then entry.Button_202:SetKeyboardFocus() end
    end
    local function open(pc,receiving)
        if valid(panel) or not valid(menu) then return end
        local tree=menu.WidgetTree
        panel=StaticConstructObject(StaticFindObject('/Script/UMG.CanvasPanel'),tree)
        local container=menu.CanvasPanel_78:AddChildToCanvas(panel)
        -- UE4SS marshals flat FVector2D arguments; nested FAnchors tables
        -- silently lose their values in this game build.
        container:SetMinimum({X=0,Y=0});container:SetMaximum({X=1,Y=1})
        container:SetOffsets({Left=0,Top=0,Right=0,Bottom=0});container:SetZOrder(10000)
        local root=panel
        local shade=StaticConstructObject(StaticFindObject('/Script/UMG.Border'),tree)
        shade:SetBrushColor({R=0,G=0,B=0,A=0.9})
        local dim=root:AddChildToCanvas(shade);dim:SetMinimum({X=0,Y=0});dim:SetMaximum({X=1,Y=1});dim:SetOffsets({Left=0,Top=0,Right=0,Bottom=0})
        local box=StaticConstructObject(StaticFindObject('/Script/UMG.VerticalBox'),tree)
        local slot=root:AddChildToCanvas(box);slot:SetMinimum({X=0.5,Y=0.5});slot:SetMaximum({X=0.5,Y=0.5})
        slot:SetAlignment({X=0.5,Y=0.5});slot:SetSize({X=1080,Y=620})
        local function text(value,size)
            local t=StaticConstructObject(StaticFindObject('/Script/UMG.TextBlock'),tree)
            t.Font.Size=size;t.Font.FontObject=menu.WB_MainMenuButtonNewInfiltratorMode.WB_StaticText.TextBlock_0.Font.FontObject
            t:SetText(FText(value));t:SetAutoWrapText(true)
            local s=box:AddChildToVerticalBox(t);s:SetPadding({Left=20,Top=10,Right=20,Bottom=20});return t
        end
        text('VERSUS',48)
        status=text('Creating private Steam lobby...',28)
        text(C.transport=='steam' and 'Experimental relay test. Invite a friend, then choose New Infiltrator Mode. Both players must run this mod.' or 'Steam invitations are available. Online matches are still in development.',26)
        inviteButton=button(pc,'INVITE FRIENDS');box:AddChildToVerticalBox(inviteButton);inviteButton:Show(0)
        if online then
            startButton=button(pc,'START INFILTRATOR MISSION');box:AddChildToVerticalBox(startButton);startButton:Show(0)
            if receiving then startButton:SetVisibility(1);inviteButton:SetVisibility(1) end
        end
        backButton=button(pc,'BACK');box:AddChildToVerticalBox(backButton);backButton:Show(0)
        panel:SetVisibility(0);menu.VerticalBox_MenuItems:SetIsEnabled(false);menu.NavigationUnlocked=false
        inviteButton.Button_202:SetKeyboardFocus()
        if online then if not receiving then online.host() end
        elseif loadNative() then native.create() else steamState={state='steam_unavailable'} end
        emit('versus_menu_opened')
    end
    local function hook()
        if hooked then return end
        RegisterHook(base..':BndEvt__Button_202_K2Node_ComponentBoundEvent_123_OnButtonClickedEvent__DelegateSignature',function(context)
            local address=context:get():GetAddress()
            if valid(entry) and address==entry:GetAddress() then pending='open'
            elseif valid(inviteButton) and address==inviteButton:GetAddress() then pending='invite'
            elseif valid(backButton) and address==backButton:GetAddress() then pending='close' end
            if valid(startButton) and address==startButton:GetAddress() then pending='start' end
        end)
        -- The game's keyboard/controller navigation activates CurrentButton.
        RegisterHook('/Game/UI/Menu/MainMenu/WB_MainMenu.WB_MainMenu_C:UpdateCurrentButton',function(context,clicked)
            if clicked:get() and valid(menu) and context:get():GetAddress()==menu:GetAddress()
                and valid(entry) and valid(menu.CurrentButton) and menu.CurrentButton:GetAddress()==entry:GetAddress() then pending='open' end
        end)
        hooked=true
    end
    local function inject(pc,found)
        menu=found;hook()
        entry=button(pc,'PLAY VERSUS')
        local box=menu.VerticalBox_MenuItems;local back=menu.WB_MainMenuButtonBack
        -- Reinsert Back after the new item; all original actions remain bound.
        local p=back.Slot.Padding
        local backPadding={Left=p.Left,Top=p.Top,Right=p.Right,Bottom=p.Bottom}
        box:RemoveChild(back);box:AddChildToVerticalBox(entry)
        local backSlot=box:AddChildToVerticalBox(back);backSlot:SetPadding(backPadding)
        entry:SetVisibility(1);lastSubmenu=false
        emit('versus_menu_entry_added')
    end
    local function update(pc)
        local now=os.clock()
        if online then steamState=online.state()
        elseif native and now>=nextPoll then
            nextPoll=now+0.2;native.poll()
            local f=io.open(C.directory..'/steam-lobby-state.txt','r')
            if f then local decoded=State.decode(f:read('*a'));f:close();if decoded then steamState=decoded end end
        end
        if not valid(pc) then return end
        local inMenu=pc:GetWorld():GetFullName():find('MAP_StartingMap',1,true)~=nil
        if not inMenu then
            if valid(panel) then close(online~=nil) end
            return
        end
        if (not valid(menu) or not valid(entry)) and now>=nextScan then
            nextScan=now+1
            for _,found in ipairs(FindAllOf('WB_MainMenu_C') or {}) do
                if valid(found) and valid(found:GetOwningPlayer()) and found:GetOwningPlayer():GetAddress()==pc:GetAddress() then inject(pc,found);break end
            end
        end
        if valid(menu) and valid(entry) then
            local submenu=menu.WB_MainMenuButtonNewInfiltratorMode:IsVisible()
            if submenu~=lastSubmenu then
                entry:SetVisibility(submenu and 0 or 1);if submenu then entry:Show(0) end
                lastSubmenu=submenu
            end
        end
        if online and C.transport=='steam' and C.role=='client' and steamState
            and steamState.state~='idle' and not valid(panel) then open(pc,true) end
        local action=pending;pending=nil
        if action=='open' then open(pc)
        elseif action=='close' then close()
        elseif action=='invite' then
            if online then online.host() elseif loadNative() then native.create() end
        elseif action=='start' and online and C.role=='host' and steamState and steamState.lobby~='0' then
            local originalMenu=menu;close(true)
            originalMenu:BndEvt__WB_MainMenuButtonNewInfiltratorMode_K2Node_ComponentBoundEvent_9_ButtonClicked__DelegateSignature()
        end
        if valid(status) then status:SetText(FText(State.message(steamState)));menu.NavigationUnlocked=false end
    end
    return {update=update,close=close,clearWorld=function()
        if not online and native then native.leave() end
        menu,entry,panel,status,inviteButton,backButton,startButton=nil,nil,nil,nil,nil,nil,nil
        pending=nil;lastSubmenu=false
    end}
end
