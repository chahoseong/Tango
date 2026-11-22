// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Containers/Ticker.h"
#include "Subsystems/GameInstanceSubsystem.h"
#include "TangoNetStatsSubsystem.generated.h"

class APlayerController;
class UCanvas;

/** Measured quality of the local client's connection to the server. */
struct FTangoMeasuredNetStats
{
	float RttMs = 0.f;
	float JitterMs = 0.f;
	float InLossPercent = 0.f;
	float OutLossPercent = 0.f;
	int32 InPacketsPerSecond = 0;
	int32 OutPacketsPerSecond = 0;
};

/**
 * Client-only debug overlay for network emulation.
 * Shows the packet simulation settings in effect next to the measured RTT / jitter / loss,
 * and logs the same values once per second (LogTangoNet) for TestNetEmulation.ps1.
 * Toggle the overlay with `tango.NetStats 0|1`. Compiled out in Shipping (DO_ENABLE_NET_TEST).
 */
UCLASS()
class UTangoNetStatsSubsystem : public UGameInstanceSubsystem
{
	GENERATED_BODY()

public:
	virtual bool ShouldCreateSubsystem(UObject* Outer) const override;
	virtual void Initialize(FSubsystemCollectionBase& Collection) override;
	virtual void Deinitialize() override;

private:
	/** Fills OutStats from the client's connection to the server. Returns false when not connected. */
	bool TryReadMeasuredStats(FTangoMeasuredNetStats& OutStats) const;

	/** One-line description of the packet simulation settings on the client's net driver. */
	FString DescribeEmulationSettings() const;

	void DrawOverlay(UCanvas* Canvas, APlayerController* PlayerController);
	bool LogStats(float DeltaTime);

	FDelegateHandle DrawHandle;
	FTSTicker::FDelegateHandle LogTickerHandle;
};
