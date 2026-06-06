import 'package:flutter/material.dart';

import '../../models/app_models.dart';
import '../owner/admin_screens.dart';

class ManagerPanel extends StatelessWidget {
  const ManagerPanel({super.key});

  @override
  Widget build(BuildContext context) => const StaffPanel(role: UserRole.manager);
}
