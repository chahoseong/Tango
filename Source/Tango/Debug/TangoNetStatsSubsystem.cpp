// Copyright Epic Games, Inc. All Rights Reserved.

#include "Debug/TangoNetStatsSubsystem.h"

#include "Debug/DebugDrawService.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "Engine/GameInstance.h"
#include "Engine/NetConnection.h"
#include "Engine/NetDriver.h"
#include "Engine/World.h"
#include "HAL/IConsoleManager.h"

DEFINE_LOG_CATEGORY_STATIC(LogTangoNet, Log, All);

bool UTangoNetStatsSubsystem::ShouldCreateSubsystem(UObject* Outer) const
{
#if DO_ENABLE_NET_TEST
	// Emulation is applied on the client only, so the overlay only makes sense there.
	return !IsRunningDedicatedServer();
#else
	return false;
#endif
}

#if DO_ENABLE_NET_TEST

namespace
{
	TAutoConsoleVariable<bool> CVarTangoNetStats(
		TEXT("tango.NetStats"),
		true,
		TEXT("Show the network emulation overlay (configured vs measured RTT / jitter / loss)."));

	constexpr float LogIntervalSeconds = 1.f;
}

void UTangoNetStatsSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);

	DrawHandle = UDebugDrawService::Register(TEXT("Game"),
		FDebugDrawDelegate::CreateUObject(this, &UTangoNetStatsSubsystem::DrawOverlay));

	LogTickerHandle = FTSTicker::GetCoreTicker().AddTicker(
		FTickerDelegate::CreateUObject(this, &UTangoNetStatsSubsystem::LogStats), LogIntervalSeconds);
}

void UTangoNetStatsSubsystem::Deinitialize()
{
	UDebugDrawService::Unregister(DrawHandle);
	FTSTicker::RemoveTicker(LogTickerHandle);

	Super::Deinitialize();
}

bool UTangoNetStatsSubsystem::TryReadMeasuredStats(FTangoMeasuredNetStats& OutStats) const
{
	const UWorld* World = GetWorld();
	const UNetDriver* NetDriver = World ? World->GetNetDriver() : nullptr;
	
	if (!NetDriver || !NetDriver->ServerConnection)
	{
		return false;
	}
	
	OutStats.RttMs = NetDriver->ServerConnection->AvgLag * 1000.0f;
	OutStats.JitterMs = NetDriver->ServerConnection->GetAverageJitterInMS();
	OutStats.InLossPercent = NetDriver->ServerConnection->GetInLossPercentage().GetAvgLossPercentage() * 100.0f;
	OutStats.OutLossPercent = NetDriver->ServerConnection->GetOutLossPercentage().GetAvgLossPercentage() * 100.0f;
	OutStats.InPacketsPerSecond = NetDriver->ServerConnection->InPacketsPerSecond;
	OutStats.OutPacketsPerSecond = NetDriver->ServerConnection->OutPacketsPerSecond;
	
	return true;
}

FString UTangoNetStatsSubsystem::DescribeEmulationSettings() const
{
	const UWorld* World = GetGameInstance()->GetWorld();
	const UNetDriver* NetDriver = World ? World->GetNetDriver() : nullptr;
	if (!NetDriver)
	{
		return TEXT("no net driver");
	}

	const FPacketSimulationSettings& Sim = NetDriver->PacketSimulationSettings;
	return FString::Printf(TEXT("Out=%d-%d In=%d-%d Loss=%d/%d"),
		Sim.PktLagMin, Sim.PktLagMax, Sim.PktIncomingLagMin, Sim.PktIncomingLagMax, Sim.PktLoss, Sim.PktIncomingLoss);
}

void UTangoNetStatsSubsystem::DrawOverlay(UCanvas* Canvas, APlayerController* PlayerController)
{
	if (!Canvas || !CVarTangoNetStats.GetValueOnGameThread())
	{
		return;
	}

	FTangoMeasuredNetStats Stats;
	const FString Measured = TryReadMeasuredStats(Stats)
		? FString::Printf(TEXT("Measured      RTT %.0fms | jitter %.0fms | loss out %.1f%% / in %.1f%% | pkt/s out %d / in %d"),
			Stats.RttMs, Stats.JitterMs, Stats.OutLossPercent, Stats.InLossPercent, Stats.OutPacketsPerSecond, Stats.InPacketsPerSecond)
		: FString(TEXT("Measured      not connected"));

	const UFont* Font = GEngine->GetSmallFont();
	Canvas->SetDrawColor(FColor::Yellow);
	Canvas->DrawText(Font, FString(TEXT("NetEmulation  ")) + DescribeEmulationSettings(), 20.f, 60.f);
	Canvas->DrawText(Font, Measured, 20.f, 76.f);
}

bool UTangoNetStatsSubsystem::LogStats(float DeltaTime)
{
	FTangoMeasuredNetStats Stats;
	if (TryReadMeasuredStats(Stats))
	{
		// Parsed by Scripts/TestNetEmulation.ps1 - keep the key=value format stable.
		UE_LOG(LogTangoNet, Log, TEXT("NetStats Emu=[%s] RttMs=%.1f JitterMs=%.1f InLoss=%.2f OutLoss=%.2f InPps=%d OutPps=%d"),
			*DescribeEmulationSettings(), Stats.RttMs, Stats.JitterMs, Stats.InLossPercent, Stats.OutLossPercent,
			Stats.InPacketsPerSecond, Stats.OutPacketsPerSecond);
	}
	return true; // keep ticking
}

#else // !DO_ENABLE_NET_TEST

void UTangoNetStatsSubsystem::Initialize(FSubsystemCollectionBase& Collection) { Super::Initialize(Collection); }
void UTangoNetStatsSubsystem::Deinitialize() { Super::Deinitialize(); }
bool UTangoNetStatsSubsystem::TryReadMeasuredStats(FTangoMeasuredNetStats&) const { return false; }
FString UTangoNetStatsSubsystem::DescribeEmulationSettings() const { return FString(); }
void UTangoNetStatsSubsystem::DrawOverlay(UCanvas*, APlayerController*) {}
bool UTangoNetStatsSubsystem::LogStats(float) { return false; }

#endif // DO_ENABLE_NET_TEST
