// Copyright Epic Games, Inc. All Rights Reserved.

using UnrealBuildTool;

public class Tango : ModuleRules
{
	public Tango(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
	
		PublicDependencyModuleNames.AddRange([
			"Core",
			"CoreUObject",
			"Engine",
			"EnhancedInput",
			"GameplayAbilities",
			"GameplayTags",
			"GameplayTasks",
			"NetCore"
		]);
	}
}
