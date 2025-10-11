local name, ns = ...;

local AceDB = LibStub('AceDB-3.0');
local AceDBOptions = LibStub('AceDBOptions-3.0');
local AceConfig = LibStub('AceConfig-3.0');
local AceConfigDialog = LibStub('AceConfigDialog-3.0');
-- LibDualSpec does not load on non-SoD classic era
local LibDualSpec = LibStub('LibDualSpec-1.0', true);

local function SortAddons(name1, name2)
  return strcmputf8i(StripHyperlinks(name1), StripHyperlinks(name2)) < 0;
end

local currentCharacterName = UnitName('player')..' - '..GetRealmName();
local DEFAULT_OPTION_KEY = 'Default';
local L;
do
  L = {
    choose_sub = 'Select one of your currently available profiles.',
    default = 'Default',
  };

  local LOCALE = GetLocale();
  if LOCALE == 'deDE' then
    L['choose_sub'] = 'Wählt ein bereits vorhandenes Profil aus.';
    L['default'] = 'Standard';
  elseif LOCALE == 'frFR' then
    L['choose_sub'] = 'Permet de choisir un des profils déjà disponibles.';
    L['default'] = 'Défaut';
  elseif LOCALE == 'koKR' then
    L['choose_sub'] = '현재 이용할 수 있는 프로필 중 하나를 선택합니다.';
    L['default'] = '기본값';
  elseif LOCALE == 'esES' or LOCALE == 'esMX' then
    L['choose_sub'] = 'Selecciona uno de los perfiles disponibles.';
    L['default'] = 'Por defecto';
  elseif LOCALE == 'zhTW' then
    L['choose_sub'] = '從當前可用的設定檔裡面選擇一個。';
    L['default'] = '預設';
  elseif LOCALE == 'zhCN' then
    L['choose_sub'] = '从当前可用的配置文件里面选择一个。';
    L['default'] = '默认';
  elseif LOCALE == 'ruRU' then
    L['choose_sub'] = 'Выбор одного из уже доступных профилей.';
    L['default'] = 'По умолчанию';
  elseif LOCALE == 'itIT' then
    L['choose_sub'] = 'Seleziona uno dei profili attualmente disponibili.';
    L['default'] = 'Predefinito';
  elseif LOCALE == 'ptBR' then
    L['choose_sub'] = 'Selecione um de seus perfis atualmente disponíveis.';
    L['default'] = 'Padrão';
  end
end

--- @class UnifiedProfileManager: FRAME
local UPM = CreateFrame('FRAME');
UPM:SetScript('OnEvent', function(self, event, ...)
  return self[event](self, ...);
end);
UPM:RegisterEvent('ADDON_LOADED');

do
  function UnifiedProfileManager_OnAddonCompartmentClick()
    UPM:OpenConfigUI();
  end
  function UnifiedProfileManager_OnAddonCompartmentEnter(_, button)
    GameTooltip:SetOwner(button, 'ANCHOR_RIGHT');
    GameTooltip:SetText('Unified Profile Manager');
    GameTooltip:AddLine(CreateAtlasMarkup('NPE_LeftClick', 18, 18) .. ' to manage your profiles', 1, 1, 1);
    GameTooltip:Show();
  end
  function UnifiedProfileManager_OnAddonCompartmentLeave()
    GameTooltip:Hide();
  end
end

function UPM:ADDON_LOADED()
  if NumyProfiler then
    --- @type NumyProfiler
    local NumyProfiler = NumyProfiler;
    NumyProfiler:WrapModules(name, 'Main', self);
  end
  UPM:UnregisterEvent('ADDON_LOADED');
  UnifiedProfileManagerDB = UnifiedProfileManagerDB or {};
  self.db = UnifiedProfileManagerDB;
  local defaults = {
    hideAddonsSetToDefault = false,
    hideAddonsWithAllAltsUsingSameProfile = false,
    hideAddonsWithAllAltsUsingCharProfile = true,
    hideAltsMatchingCurrentCharacter = false,
  };
  for property, value in pairs(defaults) do
    if self.db[property] == nil then
      self.db[property] = value;
    end
  end

  AceConfig:RegisterOptionsTable(name, self:GetOptionsTable(true));
  local panel, category = AceConfigDialog:AddToBlizOptions(name, name);

  local ignoreHook = false;
  panel:HookScript('OnShow', function()
    if ignoreHook then return; end
    ignoreHook = true;
    AceConfig:RegisterOptionsTable(name, self:GetOptionsTable());
    panel:Hide();
    panel:Show();
    RunNextFrame(function() ignoreHook = false; end);
  end);

  _G.SLASH_UNIFIED_PROFILE_MANAGER1 = '/upm';
  _G.SLASH_UNIFIED_PROFILE_MANAGER2 = '/profiles';
  SlashCmdList['UNIFIED_PROFILE_MANAGER'] = function() UPM:OpenConfigUI(); end;
end

function UPM:OpenConfigUI()
  AceConfig:RegisterOptionsTable(name, self:GetOptionsTable());
  AceConfigDialog:Open(name);
  local container = AceConfigDialog.OpenFrames[name];
  if not container or not container.frame then return; end
  container:SetTitle('Unified Profile Manager');
  container.SetTitle = nop;
  local frame = container.frame;
  frame:SetMovable(true);
  frame:SetScript('OnMouseDown', function(self)
   self:StartMoving();
  end);
  frame:SetScript('OnMouseUp', function(self)
   self:StopMovingOrSizing();
  end);
  frame.ClearAllPoints = nop;
  frame.SetPoint = nop;
end

UPM.resultCache = {};
function UPM:FindGlobal(item)
  if not self.resultCache[item] then
    for k, v in pairs(_G) do
      if item == v then
        self.resultCache[item] = k;
        break;
      end
    end
 end

  return self.resultCache[item];
end

function UPM:IsBlacklistedDB(db)
  -- some addons include debug code for LibDualSpec, which creates a database, we don't show it, cause it's nonsense and confusing to the player
  -- we scan between minors 15 and 100, for arbitrary reasons, at July 2024 we're at minor 24.
  for minor = 15, 100 do
    if db.sv == _G[('LibDualSpec-1.0-%d test'):format(minor)] then
      return true;
    end
  end

  return false;
end

function UPM:GetDuplicateAddons()
  local duplicateAddons = {};
  local addonNames = {};
  for db, _ in pairs(AceDB.db_registry) do
    if not db.parent then
      local addonName = self:GetAddonNameForDB(db);
      if addonNames[addonName] then
        duplicateAddons[addonName] = true;
      end
      addonNames[addonName] = true;
    end
  end

  return duplicateAddons;
end

UPM.dbCache = {};
function UPM:GetAddonNameForDB(db)
  if not self.dbCache[db] then
    local _, addonName = issecurevariable(db, 'sv');
    _, addonName = C_AddOns.GetAddOnInfo(addonName);
    self.dbCache[db] = addonName;
  end

  return self.dbCache[db];
end

local altHandlerPrototype = {};
do
  local CHARACTER_MAGIC_KEY = '%character%';
  local CHARACTER_REALM_MAGIC_KEY = '%character_realm%';
  local defaultProfilesProto = {
    [DEFAULT_OPTION_KEY] = L['default'],
  };
  local defaultProfilesOrder = {
    DEFAULT_OPTION_KEY,
    CHARACTER_MAGIC_KEY,
    CHARACTER_REALM_MAGIC_KEY,
  };
  local classNameFormat = '|Tinterface/icons/classicon_%s:16|t %s';
  for classID = 1, GetNumClasses() do
    local className, classFilename = GetClassInfo(classID);
    if className then
      defaultProfilesProto[classFilename] = classNameFormat:format(classFilename, className);
      table.insert(defaultProfilesOrder, classFilename);
    end
  end

  local defaultProfileCache = {};
  function altHandlerPrototype:GetDefaultProfilesForCharacter(characterName)
    if defaultProfileCache[characterName] then
      return defaultProfileCache[characterName];
    end
    if characterName == '-' then return defaultProfilesProto; end
    local defaultProfiles = Mixin({
      [characterName] = characterName,
    }, defaultProfilesProto);
    local realm = characterName:match(' %- (.+)');
    if realm then
      defaultProfiles[realm] = realm;
    end

    defaultProfileCache[characterName] = defaultProfiles;
    return defaultProfiles;
  end

 function altHandlerPrototype:ListProfiles(info)
   local db = self.db;
   local characterName = info.arg;
    local profiles = {};
    for profile, _ in pairs(db.sv.profiles) do
      profiles[profile] = profile;
    end

    for k, v in pairs(self:GetDefaultProfilesForCharacter(characterName)) do
      profiles[k] = v;
    end

    return profiles;
 end

 function altHandlerPrototype:ListOrderedProfiles(info)
    local db = self.db;
    local characterName = info.arg;
    local isAll = characterName == '-';
    local realm = characterName:match(' %- (.+)');
    local defaultProfiles = self:GetDefaultProfilesForCharacter(characterName);
    local orderedProfileKeys = {};
    for profile, _ in pairs(db.sv.profiles) do
      if not defaultProfiles[profile] then
        table.insert(orderedProfileKeys, profile);
      end
    end
    table.sort(orderedProfileKeys);

    local orderedProfiles = {};
    for _, v in ipairs(defaultProfilesOrder) do
      if not isAll and v == CHARACTER_MAGIC_KEY then
        v = characterName;
      elseif not isAll and v == CHARACTER_REALM_MAGIC_KEY then
        v = realm;
      end
      if defaultProfiles[v] then
        table.insert(orderedProfiles, v);
      end
    end
    for _, profile in ipairs(orderedProfileKeys) do
      table.insert(orderedProfiles, profile);
    end

    return orderedProfiles;
  end

 function altHandlerPrototype:GetCurrentProfile(info)
    local db = self.db;
    local characterName = info.arg;
    local isAll = characterName == '-';
    if isAll then
      local foundProfile
      for character, profile in pairs(db.sv.profileKeys) do
        if not foundProfile then
          foundProfile = profile;
        elseif profile ~= foundProfile and character ~= currentCharacterName then
          return nil;
        end
      end

      return foundProfile;
    end
    local currentProfile = db.sv and db.sv.profileKeys and db.sv.profileKeys[characterName];

    return currentProfile;
  end

  function altHandlerPrototype:SetProfile(info, profile)
    local db = self.db;
    local characterName = info.arg;
    local isAll = characterName == '-';
    if isAll then
      for character, _ in pairs(db.sv.profileKeys) do
        if character ~= currentCharacterName then
          db.sv.profileKeys[character] = profile;
        end
      end
    else
      db.sv.profileKeys[characterName] = profile;
    end
  end

  function altHandlerPrototype:IsHidden(info)
    local db = self.db;
    local characterName = info.arg;
    local currentCharactersProfile = db.sv.profileKeys[currentCharacterName];
    local profile = db.sv.profileKeys[characterName];
    if UPM.db.hideAltsMatchingCurrentCharacter and currentCharactersProfile == profile then
      return true;
    end

    return false;
  end
end

UPM.altHandlers = {};
function UPM:MakeAltOptions(db)
  if not db.sv or not db.sv.profileKeys or not next(db.sv.profileKeys) then
    return nil;
  end
  local altHandler = self.altHandlers[db] or {db = db};
  Mixin(altHandler, altHandlerPrototype);

  local increment = CreateCounter(1);
  local group = {
    type = 'group',
    name = 'Character Profiles',
    inline = true,
    order = -1, -- last
    args = {
      applyToAll = {
        name = 'Apply to all alts',
        desc = L['choose_sub'] .. ' This applies to all characters, except the current character!',
        type = 'select',
        order = increment(),
        arg = '-',
        get = 'GetCurrentProfile',
        set = 'SetProfile',
        values = 'ListProfiles',
        sorting = 'ListOrderedProfiles',
      },
      hideAltsMatchingCurrentCharacter = {
        type = 'toggle',
        name = 'Hide alts matching current character',
        desc = ('Hide alts with the same profile as %s'):format(currentCharacterName),
        order = increment(),
        get = function()
          return self.db.hideAltsMatchingCurrentCharacter;
        end,
        set = function(info, value)
          self.db.hideAltsMatchingCurrentCharacter = value;
        end,
        width = 'double',
      },
      header = {
        type = 'header',
        name = '',
        order = increment(),
      },
    },
    handler = altHandler,
  }
  local option = {
    name = '', -- character name
    desc = L['choose_sub'],
    type = 'select',
    order = 1, -- order by character name
    arg = '', -- character name
    get = 'GetCurrentProfile',
    set = 'SetProfile',
    values = 'ListProfiles',
    sorting = 'ListOrderedProfiles',
    hidden = 'IsHidden',
  };

  local orderedCharacterNames = {};
  for characterName, _ in pairs(db.sv.profileKeys) do
    table.insert(orderedCharacterNames, tostring(characterName));
  end
  table.sort(orderedCharacterNames);
  orderedCharacterNames = tInvert(orderedCharacterNames);

  local offset = increment();
  local i = 1;
  for characterName, _ in pairs(db.sv.profileKeys) do
    characterName = tostring(characterName);
    if characterName ~= currentCharacterName then
      i = i + 1;
      local charOption = CopyTable(option, true);
      charOption.name = characterName;
      charOption.arg = characterName;
      charOption.order = (orderedCharacterNames[characterName] or i) + offset;
      group.args['char'..i] = charOption;
    end
  end
  if not next(group.args) then
    return nil;
  end

  return group;
end

--- @param tbl source table
--- @param ignoredValue value that is copied raw, not recursively
--- @param copies table to store copies of tables to avoid infinite recursion
local function DeepCopyTable(tbl, ignoredValue, copies)
  copies = copies or {}
 local copy = {};
 if copies[tbl] then
    return copies[tbl];
  end
 copies[tbl] = copy;
 for k, v in pairs(tbl) do
  if type(v) == 'table' and v ~= ignoredValue then
   copy[k] = DeepCopyTable(v, ignoredValue, copies);
  else
   copy[k] = v;
  end
 end
 return copy;
end

function UPM:GetUnusedProfiles(db)
  local profiles = db.sv.profiles;
  local profileKeys = db.sv.profileKeys;
  local usedProfiles = {};
  for _, profile in pairs(profileKeys) do
    usedProfiles[profile] = true;
  end
  local unusedProfiles = {};
  for profile, _ in pairs(profiles) do
    if not usedProfiles[profile] then
      table.insert(unusedProfiles, profile);
    end
  end

  return unusedProfiles;
end

function UPM:GetAceDBOptionsTable(db)
  local options = DeepCopyTable(AceDBOptions:GetOptionsTable(db), db);

  local isLibDualSpec = LibDualSpec and LibDualSpec.registry[db] and true or false;
  if isLibDualSpec then
    LibDualSpec:EnhanceOptions(options, db);
  end

  return options;
end

function UPM:GetOptionsTable(skipAddons)
  local increment = CreateCounter(1);
  local function getOption(info)
    return self.db[info[#info]];
  end
  local function setOption(info, value)
    self.db[info[#info]] = value;
  end
  local options = {
    type = 'group',
    args = {
      ['allProfiles'] = {
        type = 'group',
        order = 0,
        name = 'All Addons',
        desc = 'Overview of all addon profiles',
        args = {
          desc = {
            type = 'description',
            name = 'You can change the profile for all addons here. Some addons may need you to reload the UI after switching, to avoid issues',
            order = increment(),
          },
          hideAddonsSetToDefault = {
            type = 'toggle',
            name = 'Hide Addons Set to ' .. L['default'],
            desc = ('Hide addons with their profile set to the %s profile'):format(L['default']),
            order = increment(),
            get = getOption,
            set = setOption,
            width = 'double',
          },
          hideAddonsWithAllAltsUsingSameProfile = {
            type = 'toggle',
            name = 'Hide Addons where all alts use the same profile',
            desc = 'Hide addons where all characters use the same profile',
            order = increment(),
            get = getOption,
            set = setOption,
            width = 'double',
          },
          hideAddonsWithAllAltsUsingCharProfile = {
            type = 'toggle',
            name = 'Hide Addons where all alts use a character specific profile',
            desc = 'Hide addons where all characters use their own character specific profile',
            order = increment(),
            get = getOption,
            set = setOption,
            width = 'double',
          },
          hideAddonsSetToCharProfile = {
            type = 'toggle',
            name = ('Hide Addons Set to %s'):format(currentCharacterName),
            desc = ('Hide addons with their profile set to %s'):format(currentCharacterName),
            order = increment(),
            get = getOption,
            set = setOption,
            width = 'double',
          },
          reloadUI = {
            type = 'execute',
            name = 'Reload UI',
            order = increment(),
            width = 'full',
            func = ReloadUI,
          },
          addons = {
            type = 'group',
            name = 'Addon Profiles',
            inline = true,
            order = increment(),
            args = {},
          }
        },
      }
    },
  }
  if skipAddons then
    return options;
  end

  local addonNames = {};
  local addonOrder = {};
  local function getOrder(info)
    local addonName = info.option.name;

    return addonOrder[addonName] or -1;
  end
  local function prune(info)
    local db = info.arg;
    local unusedProfiles = self:GetUnusedProfiles(db);
    for _, profile in ipairs(unusedProfiles) do
      db.sv.profiles[profile] = nil;
    end
  end
  local function pruneConfirmation(info)
    local db = info.arg;
    local unusedProfiles = self:GetUnusedProfiles(db);
    if #unusedProfiles == 0 then
      return false;
    end

    return ('Are you sure you want to remove %d unused profiles?\n%s'):format(#unusedProfiles, table.concat(unusedProfiles, '\n'));
  end
  local function pruneDisabled(info)
    return #self:GetUnusedProfiles(info.arg) == 0;
  end

  local addons = options.args.allProfiles.args.addons;

  local duplicateAddons = self:GetDuplicateAddons();

  for db, _ in pairs(AceDB.db_registry) do
    if not db.parent and not self:IsBlacklistedDB(db) then
      local i = increment();

      local addonName = self:GetAddonNameForDB(db);
      if duplicateAddons[addonName] then
        local savedVariableName = self:FindGlobal(db.sv);
        addonName = addonName .. (savedVariableName and WHITE_FONT_COLOR:WrapTextInColorCode(' ('..savedVariableName..')') or '');
      end

      table.insert(addonNames, addonName);

      local option = self:GetAceDBOptionsTable(db);
      option.order = getOrder;
      option.name = addonName;
      option.inline = false;
      option.args.alts = self:MakeAltOptions(db);
      option.args.prune = {
        type = 'execute',
        name = 'Prune',
        desc = 'Remove all profiles that are not used by any character',
        confirm = pruneConfirmation,
        disabled = pruneDisabled,
        order = -2,
        arg = db,
        func = prune,
      };
      options.args['profiles' .. i] = option;

      local choose = CopyTable(option.args.choose);
      choose.order = getOrder;
      choose.handler = option.handler;
      choose.name = addonName;
      choose.hidden = function()
        local currentProfile = choose.handler:GetCurrentProfile(choose);
        if self.db.hideAddonsSetToDefault and currentProfile == DEFAULT_OPTION_KEY then
          return true;
        end
        if self.db.hideAddonsSetToCharProfile and currentProfile == currentCharacterName then
          return true;
        end
        if self.db.hideAddonsWithAllAltsUsingCharProfile then
          local duplicateFound = false
          local foundProfiles = {}
          for _, v in pairs(choose.handler.db.sv.profileKeys) do
            if foundProfiles[v] then
              duplicateFound = true;
              break;
            end
            foundProfiles[v] = true;
          end
          if not duplicateFound then
            return true;
          end
        end
        if self.db.hideAddonsWithAllAltsUsingSameProfile then
          local lastSeenProfile;
          for _, v in pairs(choose.handler.db.sv.profileKeys) do
            if not lastSeenProfile then
              lastSeenProfile = v;
            elseif lastSeenProfile ~= v then
              return false;
            end
          end
          return true;
        end
      end
      addons.args['profiles' .. i] = choose;
    end
  end

  table.sort(addonNames, SortAddons);
  for i, addonName in ipairs(addonNames) do
    addonOrder[addonName] = i;
  end

  return options;
end
